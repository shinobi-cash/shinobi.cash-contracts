// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {SafeCast} from "@oz/utils/math/SafeCast.sol";

/**
 * @title ShinobiCrosschainDepositEntrypoint
 * @notice Lightweight entrypoint for cross-chain deposits on origin chains
 * @dev Deployed on origin chains (e.g., Arbitrum) where users have funds.
 * @dev Provides simple deposit/refund interface and calls ShinobiInputSettler.
 */
contract ShinobiCrosschainDepositEntrypoint is ReentrancyGuard, Ownable {
    using ShinobiIntentLib for ShinobiIntent;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the ShinobiInputSettler contract (Immutable for security)
    address public immutable inputSettler;

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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Emitted when a user initiates a cross-chain deposit
    event CrossChainDepositIntent(
        address indexed depositor,
        uint256 indexed precommitment,
        uint256 totalPaid,
        uint256 netDepositAmount,
        uint256 solverFee,
        uint256 destinationChainId,
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

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor for the Crosschain Deposit Entrypoint
     * @param _owner Initial owner of the contract
     * @param _inputSettler Address of the ShinobiInputSettler contract (made immutable)
     */
    constructor(address _owner, address _inputSettler) Ownable(_owner) {
        if (_inputSettler == address(0)) revert InvalidAddress(_inputSettler);
        inputSettler = _inputSettler;
    }

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
    // Function signature updated
    function _deposit(uint256 precommitment, uint256 _solverFeeBPS) internal {
        // --- 1. Basic Validations ---
        uint256 totalPaid = msg.value;
        if (totalPaid == 0) revert InvalidAmount();
        if (totalPaid < minimumDepositAmount) {
            revert MinimumDepositAmount(totalPaid, minimumDepositAmount);
        }
        if (destinationChainId == 0) revert ConfigurationNotSet();

        // --- 2. Fee Calculation ---
        // Accessing _solverFeeBPS directly as it is uint256
        uint256 solverFee = (totalPaid * _solverFeeBPS) / 10000;
        uint256 netDepositAmount = totalPaid - solverFee;

        // Validate deposit amount is still above minimum after solver fee deduction
        if (netDepositAmount < minimumDepositAmount) {
            revert DepositAmountBelowMinimumAfterFee(netDepositAmount, minimumDepositAmount);
        }

        // --- 3. Intent Construction ---
        // Generate global unique nonce
        uint256 intentNonce = ++nonce;

        // Calculate deadlines using SafeCast for uint256 to uint32 conversion
        uint32 currentTimestamp = block.timestamp.toUint32();
        uint32 fillDeadline = currentTimestamp + defaultFillDeadline;
        uint32 expires = currentTimestamp + defaultExpiry;

        // Empty refund calldata = simple refund to user
        bytes memory refundCalldata = "";

        // Construct input: FULL amount user paid (includes solver fee)
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), totalPaid]; // Native ETH is token 0

        // CRITICAL: Construct output.call with VERIFIED depositor and deposit amount (AFTER solver fee)
        bytes memory outputCall = abi.encodeWithSignature(
            "crosschainDeposit(address,uint256,uint256)",
            msg.sender,         // VERIFIED depositor
            netDepositAmount,   // Amount to deposit in pool (after solver fee)
            precommitment
        );

        // Construct output: Amount solver must fill on destination (AFTER solver fee)
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destinationOracle))),
            settler: bytes32(uint256(uint160(destinationOutputSettler))),
            chainId: destinationChainId,
            token: bytes32(0), // Native ETH
            amount: netDepositAmount, // Solver fills net deposit amount
            recipient: bytes32(uint256(uint160(destinationEntrypoint))),
            call: outputCall,
            context: ""
        });

        // Construct ShinobiIntent with msg.sender as depositor
        ShinobiIntent memory intent = ShinobiIntent({
            user: msg.sender, // CRITICAL: Verified depositor
            nonce: intentNonce,
            originChainId: block.chainid,
            expires: expires,
            fillDeadline: fillDeadline,
            fillOracle: fillOracle,
            inputs: inputs,
            outputs: outputs,
            intentOracle: intentOracle,
            refundCalldata: refundCalldata
        });

        // Calculate orderId for event emission
        bytes32 orderId = intent.orderIdentifier();

        // --- 4. Call Settler & Emit Event ---

        // Emit event for indexers to track deposit initiation
        emit CrossChainDepositIntent(
            msg.sender,
            precommitment,
            totalPaid,
            netDepositAmount,
            solverFee,
            destinationChainId,
            orderId
        );

        // Call ShinobiInputSettler to open intent and escrow funds
        IShinobiInputSettler(inputSettler).open{value: totalPaid}(intent);
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
}