// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {IHyperlaneOracle} from "../oif/interfaces/IHyperlaneOracle.sol";
import {IPayloadCreator} from "../oif/interfaces/IPayloadCreator.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@oz/access/Ownable2Step.sol";
import {SafeCast} from "@oz/utils/math/SafeCast.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCrosschainDepositEntrypoint
 * @author Karandeep Singh
 * @notice Lightweight entrypoint for cross-chain deposits on origin chains
 * @dev Deployed on origin chains where users have funds. Provides deposit/refund interface.
 */
contract ShinobiCrosschainDepositEntrypoint is ReentrancyGuard, Ownable2Step, IPayloadCreator {
    using ShinobiIntentLib for ShinobiIntent;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public inputSettler;
    bool private inputSettlerSet;

    uint32 public defaultFillDeadline = 30 minutes;
    uint32 public defaultExpiry = 24 hours;
    address public fillOracle;
    address public intentOracle;
    uint256 public destinationChainId;
    address public destinationEntrypoint;
    address public destinationOutputSettler;
    address public destinationOracle;

    uint256 public minimumDepositAmount = 0.01 ether;
    uint256 public defaultSolverFeeBPS = 500;
    uint256 public maxSolverFeeBPS = 1000;
    uint256 public nonce;

    mapping(address => address) public assetToPool;

    /// @notice Tracks used precommitments to prevent duplicate deposits on this chain
    mapping(uint256 => bool) public usedPrecommitments;

    /*//////////////////////////////////////////////////////////////
                        HYPERLANE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    IHyperlaneOracle public hyperlaneOracle;
    uint32 public destinationHyperlaneDomain;
    address public destinationHyperlaneOracle;
    uint256 public hyperlaneGasLimit = 200_000;
    mapping(bytes32 => bool) public validIntentPayloads;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event InputSettlerSet(address indexed inputSettlerAddress);
    event DefaultDeadlinesUpdated(uint32 newFillDeadline, uint32 newExpiry);
    event FillOracleUpdated(address indexed previousFillOracle, address indexed newFillOracle);
    event IntentOracleUpdated(address indexed previousIntentOracle, address indexed newIntentOracle);
    event DestinationConfigUpdated(
        uint256 indexed chainId,
        address indexed entrypoint,
        address outputSettler,
        address oracle
    );
    event MinimumDepositAmountUpdated(uint256 previousMinimum, uint256 newMinimum);
    event DefaultSolverFeeBPSUpdated(uint256 previousFeeBPS, uint256 newFeeBPS);
    event MaxSolverFeeBPSUpdated(uint256 previousMaxFeeBPS, uint256 newMaxFeeBPS);
    event AssetPoolConfigured(address indexed asset, address indexed pool);
    event AssetPoolRemoved(address indexed asset);
    event HyperlaneConfigUpdated(
        address indexed hyperlaneOracle,
        uint32 destinationDomain,
        address indexed destinationOracle,
        uint256 gasLimit
    );
    event IntentProofSubmitted(bytes32 indexed orderId, uint256 hyperlaneGasPayment);
    event CrossChainDepositIntent(
        address indexed depositor,
        uint256 indexed precommitment,
        uint256 totalPaid,
        uint256 netDepositAmount,
        uint256 solverFee,
        uint256 destinationChainId,
        address asset,
        address destinationPool,
        bytes32 indexed orderId
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error MinimumDepositAmount(uint256 receivedAmount, uint256 requiredMinimum);
    error DepositAmountBelowMinimumAfterFee(uint256 netDepositAmount, uint256 requiredMinimum);
    error SolverFeeExceedsMax(uint256 providedFee, uint256 maxFee);
    error InvalidFeeBPS(uint256 providedFee);
    error ConfigurationNotSet();
    error InvalidAddress(address providedAddress);
    error InvalidChainId(uint256 providedChainId);
    error AssetNotSupported(address asset);
    error HyperlaneNotConfigured();
    error InsufficientFundsForHyperlane(uint256 available, uint256 required);
    error PrecommitmentAlreadyUsed();
    error ExpiryBeforeFillDeadline();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit funds for cross-chain transfer to pool (uses default solver fee)
     * @param precommitment The precommitment for the pool deposit
     */
    function deposit(uint256 precommitment) external payable nonReentrant {
        _deposit(precommitment, defaultSolverFeeBPS);
    }

    /**
     * @notice Deposit funds for cross-chain transfer to pool with custom solver fee
     * @param precommitment The precommitment for the pool deposit
     * @param customSolverFeeBPS Custom solver fee in basis points (e.g., 700 = 7%)
     */
    // Function signature updated
    function depositWithCustomFee(uint256 precommitment, uint256 customSolverFeeBPS) external payable nonReentrant {
        if (customSolverFeeBPS > maxSolverFeeBPS) {
            revert SolverFeeExceedsMax(customSolverFeeBPS, maxSolverFeeBPS);
        }
        _deposit(precommitment, customSolverFeeBPS);
    }

    function _deposit(uint256 precommitment, uint256 _solverFeeBPS) internal {
        uint256 totalPaid = msg.value;
        if (totalPaid == 0) revert InvalidAmount();
        if (destinationChainId == 0) revert ConfigurationNotSet();
        if (assetToPool[Constants.NATIVE_ASSET] == address(0)) revert AssetNotSupported(Constants.NATIVE_ASSET);

        // Prevent duplicate precommitment usage on this chain
        if (usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        usedPrecommitments[precommitment] = true;

        uint256 hyperlaneGasPayment = _quoteHyperlaneGasPayment();
        if (hyperlaneGasPayment > 0 && totalPaid <= hyperlaneGasPayment) {
            revert InsufficientFundsForHyperlane(totalPaid, hyperlaneGasPayment);
        }

        uint256 depositFunds = totalPaid - hyperlaneGasPayment;
        uint256 solverFee = (depositFunds * _solverFeeBPS) / 10000;
        uint256 netDepositAmount = depositFunds - solverFee;

        if (netDepositAmount < minimumDepositAmount) {
            revert DepositAmountBelowMinimumAfterFee(netDepositAmount, minimumDepositAmount);
        }

        bytes32 orderId = _createAndExecuteIntent(precommitment, depositFunds, netDepositAmount);

        if (hyperlaneGasPayment > 0) {
            _submitIntentProofToHyperlane(orderId, hyperlaneGasPayment);
        }

        emit CrossChainDepositIntent(
            msg.sender,
            precommitment,
            totalPaid,
            netDepositAmount,
            solverFee,
            destinationChainId,
            Constants.NATIVE_ASSET,
            assetToPool[Constants.NATIVE_ASSET],
            orderId
        );
    }

    function _quoteHyperlaneGasPayment() internal view returns (uint256 gasPayment) {
        if (address(hyperlaneOracle) == address(0)) return 0;

        bytes[] memory tempPayloads = new bytes[](1);
        tempPayloads[0] = abi.encode(bytes32(0));

        return hyperlaneOracle.quoteGasPayment(
            destinationHyperlaneDomain,
            destinationHyperlaneOracle,
            hyperlaneGasLimit,
            "",
            address(this),
            tempPayloads
        );
    }

    function _createAndExecuteIntent(
        uint256 precommitment,
        uint256 depositFunds,
        uint256 netDepositAmount
    ) internal returns (bytes32 orderId) {
        uint256 intentNonce = ++nonce;
        uint32 currentTimestamp = block.timestamp.toUint32();

        {
            uint256[2][] memory inputs = new uint256[2][](1);
            inputs[0] = [uint256(0), depositFunds];

            MandateOutput[] memory outputs = new MandateOutput[](1);
            outputs[0] = _buildOutput(netDepositAmount, precommitment);

            ShinobiIntent memory intent = ShinobiIntent({
                user: msg.sender,
                nonce: intentNonce,
                originChainId: block.chainid,
                expires: currentTimestamp + defaultExpiry,
                fillDeadline: currentTimestamp + defaultFillDeadline,
                fillOracle: fillOracle,
                inputs: inputs,
                outputs: outputs,
                intentOracle: intentOracle,
                refundCalldata: ""
            });

            orderId = intent.orderIdentifier();
            validIntentPayloads[orderId] = true;
            IShinobiInputSettler(inputSettler).open{value: depositFunds}(intent);
        }
    }

    function _buildOutput(
        uint256 netDepositAmount,
        uint256 precommitment
    ) internal view returns (MandateOutput memory output) {
        bytes memory outputCall = abi.encodeWithSignature(
            "crosschainDeposit(address,uint256,uint256)",
            msg.sender,
            netDepositAmount,
            precommitment
        );

        output = MandateOutput({
            oracle: bytes32(uint256(uint160(destinationOracle))),
            settler: bytes32(uint256(uint160(destinationOutputSettler))),
            chainId: destinationChainId,
            token: bytes32(0),
            amount: netDepositAmount,
            recipient: bytes32(uint256(uint160(destinationEntrypoint))),
            call: outputCall,
            context: ""
        });
    }

    function _submitIntentProofToHyperlane(bytes32 orderId, uint256 gasPayment) internal {
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encode(orderId);

        hyperlaneOracle.submit{value: gasPayment}(
            destinationHyperlaneDomain,
            destinationHyperlaneOracle,
            hyperlaneGasLimit,
            "",
            address(this),
            payloads
        );

        emit IntentProofSubmitted(orderId, gasPayment);
    }

    /**
     * @notice Request refund for expired deposit
     * @dev Can be called by anyone after intent expiry. Funds always sent to intent.user.
     */
    function refund(ShinobiIntent calldata intent) external nonReentrant {
        IShinobiInputSettler(inputSettler).refund(intent);
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setInputSettler(address _inputSettler) external onlyOwner {
        if (_inputSettler == address(0)) revert InvalidAddress(_inputSettler);
        inputSettler = _inputSettler;
        inputSettlerSet = true;
        emit InputSettlerSet(_inputSettler);
    }

    function setDefaultDeadlines(uint32 _fillDeadline, uint32 _expiry) external onlyOwner {
        if (_expiry <= _fillDeadline) revert ExpiryBeforeFillDeadline();
        defaultFillDeadline = _fillDeadline;
        defaultExpiry = _expiry;
        emit DefaultDeadlinesUpdated(_fillDeadline, _expiry);
    }

    function setFillOracle(address _fillOracle) external onlyOwner {
        address previousFillOracle = fillOracle;
        fillOracle = _fillOracle;
        emit FillOracleUpdated(previousFillOracle, _fillOracle);
    }

    function setIntentOracle(address _intentOracle) external onlyOwner {
        address previousIntentOracle = intentOracle;
        intentOracle = _intentOracle;
        emit IntentOracleUpdated(previousIntentOracle, _intentOracle);
    }

    function setDestinationConfig(
        uint256 _chainId,
        address _entrypoint,
        address _outputSettler,
        address _oracle
    ) external onlyOwner {
        if (_chainId == 0) revert InvalidChainId(_chainId);
        if (_entrypoint == address(0)) revert InvalidAddress(_entrypoint);
        if (_outputSettler == address(0)) revert InvalidAddress(_outputSettler);
        if (_oracle == address(0)) revert InvalidAddress(_oracle);

        destinationChainId = _chainId;
        destinationEntrypoint = _entrypoint;
        destinationOutputSettler = _outputSettler;
        destinationOracle = _oracle;

        emit DestinationConfigUpdated(_chainId, _entrypoint, _outputSettler, _oracle);
    }

    function setAssetPool(address _asset, address _pool) external onlyOwner {
        if (_pool == address(0)) revert InvalidAddress(_pool);
        assetToPool[_asset] = _pool;
        emit AssetPoolConfigured(_asset, _pool);
    }

    function removeAssetPool(address _asset) external onlyOwner {
        delete assetToPool[_asset];
        emit AssetPoolRemoved(_asset);
    }

    function setMinimumDepositAmount(uint256 _minimumAmount) external onlyOwner {
        uint256 previousMinimum = minimumDepositAmount;
        minimumDepositAmount = _minimumAmount;
        emit MinimumDepositAmountUpdated(previousMinimum, _minimumAmount);
    }

    function setDefaultSolverFeeBPS(uint256 _feeBPS) external onlyOwner {
        if (_feeBPS > maxSolverFeeBPS) revert SolverFeeExceedsMax(_feeBPS, maxSolverFeeBPS);
        uint256 previousFeeBPS = defaultSolverFeeBPS;
        defaultSolverFeeBPS = _feeBPS;
        emit DefaultSolverFeeBPSUpdated(previousFeeBPS, _feeBPS);
    }

    function setMaxSolverFeeBPS(uint256 _maxFeeBPS) external onlyOwner {
        if (_maxFeeBPS > 10000) revert InvalidFeeBPS(_maxFeeBPS);
        if (defaultSolverFeeBPS > _maxFeeBPS) revert SolverFeeExceedsMax(defaultSolverFeeBPS, _maxFeeBPS);
        uint256 previousMaxFeeBPS = maxSolverFeeBPS;
        maxSolverFeeBPS = _maxFeeBPS;
        emit MaxSolverFeeBPSUpdated(previousMaxFeeBPS, _maxFeeBPS);
    }

    /*//////////////////////////////////////////////////////////////
                    HYPERLANE CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setHyperlaneConfig(
        address _hyperlaneOracle,
        uint32 _destinationDomain,
        address _destinationOracle,
        uint256 _gasLimit
    ) external onlyOwner {
        if (_hyperlaneOracle == address(0)) revert InvalidAddress(_hyperlaneOracle);
        if (_destinationOracle == address(0)) revert InvalidAddress(_destinationOracle);
        if (_gasLimit == 0) revert InvalidAmount();

        hyperlaneOracle = IHyperlaneOracle(_hyperlaneOracle);
        destinationHyperlaneDomain = _destinationDomain;
        destinationHyperlaneOracle = _destinationOracle;
        hyperlaneGasLimit = _gasLimit;

        emit HyperlaneConfigUpdated(_hyperlaneOracle, _destinationDomain, _destinationOracle, _gasLimit);
    }

    function disableHyperlane() external onlyOwner {
        hyperlaneOracle = IHyperlaneOracle(address(0));
        emit HyperlaneConfigUpdated(address(0), 0, address(0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    IPAYLOADCREATOR IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayloadCreator
    function arePayloadsValid(bytes[] calldata payloads) external view override returns (bool valid) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes32 orderId = abi.decode(payloads[i], (bytes32));
            if (!validIntentPayloads[orderId]) return false;
        }
        return true;
    }
}