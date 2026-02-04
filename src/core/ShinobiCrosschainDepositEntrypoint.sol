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
import {Ownable} from "@oz/access/Ownable.sol";
import {SafeCast} from "@oz/utils/math/SafeCast.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCrosschainDepositEntrypoint
 * @notice Lightweight entrypoint for cross-chain deposits on origin chains
 * @dev Deployed on origin chains (e.g., Arbitrum) where users have funds.
 * @dev Provides simple deposit/refund interface and calls ShinobiInputSettler.
 */
contract ShinobiCrosschainDepositEntrypoint is ReentrancyGuard, Ownable, IPayloadCreator {
    using ShinobiIntentLib for ShinobiIntent;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the ShinobiInputSettler contract (Immutable for security)
    address public inputSettler;

    /// @notice Flag to ensure the inputSettler is only set once
    bool private inputSettlerSet;

    /// @notice Default configuration for cross-chain deposits
    uint32 public defaultFillDeadline = 1 hours;
    uint32 public defaultExpiry = 24 hours;
    address public fillOracle;
    address public intentOracle;
    uint256 public destinationChainId;
    address public destinationEntrypoint;
    address public destinationOutputSettler;
    address public destinationOracle;

    /// @notice Minimum deposit amount in wei (prevents uneconomical deposits)
    uint256 public minimumDepositAmount = 0.01 ether;

    /// @notice Default solver fee in basis points (e.g., 500 = 5%)
    // Changed to uint256
    uint256 public defaultSolverFeeBPS = 500; 

    /// @notice Maximum allowed solver fee in basis points (e.g., 1000 = 10%)
    // Changed to uint256
    uint256 public maxSolverFeeBPS = 1000;

    /// @notice Global nonce for generating unique order IDs
    uint256 public nonce;

    /// @notice Mapping of asset address to destination pool address
    /// @dev Use Constants.NATIVE_ASSET for native ETH
    mapping(address => address) public assetToPool;

    /*//////////////////////////////////////////////////////////////
                        HYPERLANE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice HyperlaneOracle contract on origin chain for submitting intent proofs
    IHyperlaneOracle public hyperlaneOracle;

    /// @notice Hyperlane domain ID of the destination chain
    uint32 public destinationHyperlaneDomain;

    /// @notice HyperlaneOracle address on destination chain
    address public destinationHyperlaneOracle;

    /// @notice Gas limit for Hyperlane message execution on destination
    uint256 public hyperlaneGasLimit = 200_000;

    /// @notice Tracks valid intent orderIds for IPayloadCreator validation
    /// @dev Set to true when intent is created, checked by HyperlaneOracle
    mapping(bytes32 => bool) public validIntentPayloads;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the ShinobiInputSettler address is set
    event InputSettlerSet(address indexed inputSettlerAddress);

    /// @notice Emitted when the default fill deadline is updated
    event DefaultFillDeadlineUpdated(uint32 previousFillDeadline, uint32 newFillDeadline);

    /// @notice Emitted when the default expiry is updated
    event DefaultExpiryUpdated(uint32 previousExpiry, uint32 newExpiry);

    /// @notice Emitted when the fill oracle address is updated
    event FillOracleUpdated(address indexed previousFillOracle, address indexed newFillOracle);

    /// @notice Emitted when the intent oracle address is updated
    event IntentOracleUpdated(address indexed previousIntentOracle, address indexed newIntentOracle);

    /// @notice Emitted when the destination chain configuration is updated
    event DestinationConfigUpdated(
        uint256 indexed chainId,
        address indexed entrypoint,
        address outputSettler,
        address oracle
    );

    /// @notice Emitted when the minimum deposit amount is updated
    event MinimumDepositAmountUpdated(uint256 previousMinimum, uint256 newMinimum);

    /// @notice Emitted when the default solver fee BPS is updated
    // Event signature updated
    event DefaultSolverFeeBPSUpdated(uint256 previousFeeBPS, uint256 newFeeBPS);

    /// @notice Emitted when the maximum solver fee BPS is updated
    // Event signature updated
    event MaxSolverFeeBPSUpdated(uint256 previousMaxFeeBPS, uint256 newMaxFeeBPS);

    /// @notice Emitted when an asset-to-pool mapping is configured
    event AssetPoolConfigured(address indexed asset, address indexed pool);

    /// @notice Emitted when an asset-to-pool mapping is removed
    event AssetPoolRemoved(address indexed asset);

    /// @notice Emitted when Hyperlane configuration is updated
    event HyperlaneConfigUpdated(
        address indexed hyperlaneOracle,
        uint32 destinationDomain,
        address indexed destinationOracle,
        uint256 gasLimit
    );

    /// @notice Emitted when intent proof is submitted to Hyperlane
    event IntentProofSubmitted(bytes32 indexed orderId, uint256 hyperlaneGasPayment);

    /// @notice Emitted when a user initiates a cross-chain deposit
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

    /// @notice Thrown when deposit amount is zero
    error InvalidAmount();

    /// @notice Thrown when deposit amount is below minimum
    error MinimumDepositAmount(uint256 receivedAmount, uint256 requiredMinimum);

    /// @notice Thrown when deposit amount after solver fee is below minimum
    error DepositAmountBelowMinimumAfterFee(uint256 netDepositAmount, uint256 requiredMinimum);

    /// @notice Thrown when solver fee exceeds maximum allowed
    // Error signature updated
    error SolverFeeExceedsMax(uint256 providedFee, uint256 maxFee);

    /// @notice Thrown when fee BPS is invalid (> 10000)
    // Error signature updated
    error InvalidFeeBPS(uint256 providedFee);

    /// @notice Thrown when destination chain configuration is not set
    error ConfigurationNotSet();

    /// @notice Thrown when setter is called with zero address
    error InvalidAddress(address providedAddress);

    /// @notice Thrown when chain ID is zero
    error InvalidChainId(uint256 providedChainId);

    /// @notice Thrown when asset is not configured with a destination pool
    error AssetNotSupported(address asset);

    /// @notice Thrown when Hyperlane oracle is not configured
    error HyperlaneNotConfigured();

    /// @notice Thrown when deposit amount is insufficient to cover Hyperlane gas
    error InsufficientFundsForHyperlane(uint256 available, uint256 required);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor for the Crosschain Deposit Entrypoint
     * @param _owner Initial owner of the contract
     */
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

    /**
     * @notice Internal deposit implementation with configurable solver fee
     * @param precommitment The precommitment for the pool deposit
     * @param _solverFeeBPS Solver fee in basis points to use for this deposit
     */
    function _deposit(uint256 precommitment, uint256 _solverFeeBPS) internal {
        // --- 1. Basic Validations ---
        uint256 totalPaid = msg.value;
        if (totalPaid == 0) revert InvalidAmount();
        if (destinationChainId == 0) revert ConfigurationNotSet();
        if (assetToPool[Constants.NATIVE_ASSET] == address(0)) revert AssetNotSupported(Constants.NATIVE_ASSET);

        // --- 2. Quote Hyperlane & Calculate Fees ---
        uint256 hyperlaneGasPayment = _quoteHyperlaneGasPayment();

        // Validate sufficient funds for Hyperlane
        if (hyperlaneGasPayment > 0 && totalPaid <= hyperlaneGasPayment) {
            revert InsufficientFundsForHyperlane(totalPaid, hyperlaneGasPayment);
        }

        uint256 depositFunds = totalPaid - hyperlaneGasPayment;
        uint256 solverFee = (depositFunds * _solverFeeBPS) / 10000;
        uint256 netDepositAmount = depositFunds - solverFee;

        // Validate netDepositAmount (amount going to pool) meets minimum
        // This is the critical check - pool will reject deposits below its minimum
        if (netDepositAmount < minimumDepositAmount) {
            revert DepositAmountBelowMinimumAfterFee(netDepositAmount, minimumDepositAmount);
        }

        // --- 3. Create Intent and Execute ---
        bytes32 orderId = _createAndExecuteIntent(precommitment, depositFunds, netDepositAmount);

        // --- 4. Submit Intent Proof to Hyperlane (if configured) ---
        if (hyperlaneGasPayment > 0) {
            _submitIntentProofToHyperlane(orderId, hyperlaneGasPayment);
        }

        // --- 5. Emit Event ---
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

    /**
     * @notice Quote Hyperlane gas payment if configured
     * @return gasPayment The required gas payment, or 0 if Hyperlane not configured
     */
    function _quoteHyperlaneGasPayment() internal view returns (uint256 gasPayment) {
        if (address(hyperlaneOracle) == address(0)) {
            return 0;
        }

        bytes[] memory tempPayloads = new bytes[](1);
        tempPayloads[0] = abi.encode(bytes32(0)); // Placeholder, actual orderId doesn't affect gas quote

        return hyperlaneOracle.quoteGasPayment(
            destinationHyperlaneDomain,
            destinationHyperlaneOracle,
            hyperlaneGasLimit,
            "",
            address(this),
            tempPayloads
        );
    }

    /**
     * @notice Create intent and execute on InputSettler
     * @param precommitment The deposit precommitment
     * @param depositFunds Amount to escrow in InputSettler
     * @param netDepositAmount Amount solver will fill (after fees)
     * @return orderId The unique order identifier
     */
    function _createAndExecuteIntent(
        uint256 precommitment,
        uint256 depositFunds,
        uint256 netDepositAmount
    ) internal returns (bytes32 orderId) {
        uint256 intentNonce = ++nonce;
        uint32 currentTimestamp = block.timestamp.toUint32();

        // Build intent in nested block to manage stack
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

    /**
     * @notice Build MandateOutput for deposit intent
     * @param netDepositAmount Amount to deposit in pool
     * @param precommitment The deposit precommitment
     * @return output The constructed MandateOutput
     */
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

    /**
     * @notice Submit intent proof to Hyperlane for relay to destination chain
     * @param orderId The unique order identifier to prove
     * @param gasPayment The pre-quoted gas payment for Hyperlane
     */
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
     * @dev Can be called by anyone after intent expiry. Funds are always sent to intent.user.
     * @param intent The original deposit intent
     */
    function refund(ShinobiIntent calldata intent) external nonReentrant {
        // inputSettler is immutable, no address(0) check needed
        IShinobiInputSettler(inputSettler).refund(intent);
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the ShinobiInputSettler address (can only be called once by owner)
     * @param _inputSettler Address of the ShinobiInputSettler contract
     */
    function setInputSettler(address _inputSettler) external onlyOwner {
        if (_inputSettler == address(0)) revert InvalidAddress(_inputSettler);
        
        inputSettler = _inputSettler;
        inputSettlerSet = true;
        
        emit InputSettlerSet(_inputSettler);
    }

    /**
     * @notice Set default fill deadline duration
     * @param _fillDeadline Fill deadline in seconds from now
     */
    function setDefaultFillDeadline(uint32 _fillDeadline) external onlyOwner {
        uint32 previousFillDeadline = defaultFillDeadline;
        defaultFillDeadline = _fillDeadline;
        emit DefaultFillDeadlineUpdated(previousFillDeadline, _fillDeadline);
    }

    /**
     * @notice Set default expiry duration
     * @param _expiry Expiry in seconds from now
     */
    function setDefaultExpiry(uint32 _expiry) external onlyOwner {
        uint32 previousExpiry = defaultExpiry;
        defaultExpiry = _expiry;
        emit DefaultExpiryUpdated(previousExpiry, _expiry);
    }

    /**
     * @notice Set fill oracle address
     * @param _fillOracle Fill oracle address
     */
    function setFillOracle(address _fillOracle) external onlyOwner {
        address previousFillOracle = fillOracle;
        fillOracle = _fillOracle;
        emit FillOracleUpdated(previousFillOracle, _fillOracle);
    }

    /**
     * @notice Set intent oracle address
     * @param _intentOracle Intent oracle address
     */
    function setIntentOracle(address _intentOracle) external onlyOwner {
        address previousIntentOracle = intentOracle;
        intentOracle = _intentOracle;
        emit IntentOracleUpdated(previousIntentOracle, _intentOracle);
    }

    /**
     * @notice Set destination chain configuration
     * @param _chainId Destination chain ID (where pool is deployed)
     * @param _entrypoint Destination ShinobiCashEntrypoint address
     * @param _outputSettler Destination ShinobiOutputSettler address
     * @param _oracle Destination oracle address
     */
    function setDestinationConfig(
        uint256 _chainId,
        address _entrypoint,
        address _outputSettler,
        address _oracle
    ) external onlyOwner {
        // SECURITY: Validate all configuration parameters
        if (_chainId == 0) revert InvalidChainId(_chainId);
        if (_entrypoint == address(0)) revert InvalidAddress(_entrypoint);
        if (_outputSettler == address(0)) revert InvalidAddress(_outputSettler);
        if (_oracle == address(0)) revert InvalidAddress(_oracle);

        // Update destination chain configuration
        destinationChainId = _chainId;
        destinationEntrypoint = _entrypoint;
        destinationOutputSettler = _outputSettler;
        destinationOracle = _oracle;

        emit DestinationConfigUpdated(_chainId, _entrypoint, _outputSettler, _oracle);
    }

    /**
     * @notice Configure asset to destination pool mapping
     * @param _asset Asset address (use Constants.NATIVE_ASSET for native ETH)
     * @param _pool Destination pool address on the destination chain
     */
    function setAssetPool(address _asset, address _pool) external onlyOwner {
        if (_pool == address(0)) revert InvalidAddress(_pool);
        assetToPool[_asset] = _pool;
        emit AssetPoolConfigured(_asset, _pool);
    }

    /**
     * @notice Remove asset to pool mapping (disables deposits for this asset)
     * @param _asset Asset address to remove
     */
    function removeAssetPool(address _asset) external onlyOwner {
        delete assetToPool[_asset];
        emit AssetPoolRemoved(_asset);
    }

    /**
     * @notice Set minimum deposit amount
     * @param _minimumAmount Minimum deposit amount in wei
     */
    function setMinimumDepositAmount(uint256 _minimumAmount) external onlyOwner {
        uint256 previousMinimum = minimumDepositAmount;
        minimumDepositAmount = _minimumAmount;
        emit MinimumDepositAmountUpdated(previousMinimum, _minimumAmount);
    }

    /**
     * @notice Set default solver fee in basis points
     * @param _feeBPS Solver fee in basis points (e.g., 500 = 5%)
     */
    // Function signature updated
    function setDefaultSolverFeeBPS(uint256 _feeBPS) external onlyOwner {
        if (_feeBPS > maxSolverFeeBPS) {
            revert SolverFeeExceedsMax(_feeBPS, maxSolverFeeBPS);
        }
        uint256 previousFeeBPS = defaultSolverFeeBPS;
        defaultSolverFeeBPS = _feeBPS;
        emit DefaultSolverFeeBPSUpdated(previousFeeBPS, _feeBPS);
    }

    /**
     * @notice Set maximum solver fee in basis points
     * @param _maxFeeBPS Maximum solver fee in basis points (e.g., 1000 = 10%)
     */
    // Function signature updated
    function setMaxSolverFeeBPS(uint256 _maxFeeBPS) external onlyOwner {
        if (_maxFeeBPS > 10000) revert InvalidFeeBPS(_maxFeeBPS); // Max 100%
        // Ensure default fee is not greater than the new max
        if (defaultSolverFeeBPS > _maxFeeBPS) {
             revert SolverFeeExceedsMax(defaultSolverFeeBPS, _maxFeeBPS);
        }
        uint256 previousMaxFeeBPS = maxSolverFeeBPS;
        maxSolverFeeBPS = _maxFeeBPS;
        emit MaxSolverFeeBPSUpdated(previousMaxFeeBPS, _maxFeeBPS);
    }

    /*//////////////////////////////////////////////////////////////
                    HYPERLANE CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure Hyperlane oracle for intent proof relay
     * @param _hyperlaneOracle Address of HyperlaneOracle on this chain
     * @param _destinationDomain Hyperlane domain ID of destination chain
     * @param _destinationOracle Address of HyperlaneOracle on destination chain
     * @param _gasLimit Gas limit for message execution on destination
     */
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

    /**
     * @notice Disable Hyperlane integration (revert to MockOracle behavior)
     * @dev Sets hyperlaneOracle to address(0), disabling proof relay
     */
    function disableHyperlane() external onlyOwner {
        hyperlaneOracle = IHyperlaneOracle(address(0));
        emit HyperlaneConfigUpdated(address(0), 0, address(0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    IPAYLOADCREATOR IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate that payloads were created by this contract
     * @dev Called by HyperlaneOracle before relaying payloads
     * @param payloads Array of encoded orderIds to validate
     * @return valid True if all payloads are valid intent orderIds
     */
    function arePayloadsValid(bytes[] calldata payloads) external view override returns (bool valid) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes32 orderId = abi.decode(payloads[i], (bytes32));
            if (!validIntentPayloads[orderId]) {
                return false;
            }
        }
        return true;
    }
}