// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title ShinobiCrosschainDepositEntrypoint
 * @notice Lightweight entrypoint for cross-chain deposits on origin chains
 * @dev Deployed on origin chains (e.g., Arbitrum) where users have funds
 * @dev Provides simple deposit/refund interface and calls ShinobiInputSettler
 */
contract ShinobiCrosschainDepositEntrypoint is ReentrancyGuard, Ownable {
    using ShinobiIntentLib for ShinobiIntent;
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the ShinobiInputSettler contract
    address public inputSettler;

    /// @notice Default configuration for cross-chain deposits
    uint32 public defaultFillDeadline = 1 hours;
    uint32 public defaultExpiry = 24 hours;
    address public fillOracle;
    address public intentOracle;
    uint256 public destinationChainId;
    address public destinationEntrypoint;
    address public destinationOutputSettler;
    address public destinationOracle;

    /// @notice Global nonce for generating unique order IDs
    uint256 public nonce;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the ShinobiInputSettler address is updated
    /// @param previousInputSettler The previous ShinobiInputSettler address
    /// @param newInputSettler The new ShinobiInputSettler address
    event InputSettlerUpdated(address indexed previousInputSettler, address indexed newInputSettler);

    /// @notice Emitted when the default fill deadline is updated
    /// @param previousFillDeadline The previous default fill deadline
    /// @param newFillDeadline The new default fill deadline
    event DefaultFillDeadlineUpdated(uint32 previousFillDeadline, uint32 newFillDeadline);

    /// @notice Emitted when the default expiry is updated
    /// @param previousExpiry The previous default expiry
    /// @param newExpiry The new default expiry
    event DefaultExpiryUpdated(uint32 previousExpiry, uint32 newExpiry);

    /// @notice Emitted when the fill oracle address is updated
    /// @param previousFillOracle The previous fill oracle address
    /// @param newFillOracle The new fill oracle address
    event FillOracleUpdated(address indexed previousFillOracle, address indexed newFillOracle);

    /// @notice Emitted when the intent oracle address is updated
    /// @param previousIntentOracle The previous intent oracle address
    /// @param newIntentOracle The new intent oracle address
    event IntentOracleUpdated(address indexed previousIntentOracle, address indexed newIntentOracle);

    /// @notice Emitted when the destination chain configuration is updated
    /// @param chainId The destination chain ID
    /// @param entrypoint The destination ShinobiCashEntrypoint address
    /// @param outputSettler The destination ShinobiOutputSettler address
    /// @param oracle The destination oracle address
    event DestinationConfigUpdated(
        uint256 indexed chainId,
        address indexed entrypoint,
        address outputSettler,
        address oracle
    );

    /// @notice Emitted when a user initiates a cross-chain deposit
    /// @param depositor The address initiating the deposit
    /// @param precommitment The precommitment for the pool deposit
    /// @param amount The amount being deposited
    /// @param destinationChainId The destination chain where deposit will be processed
    /// @param orderId The unique order identifier for tracking (links to InputSettler.Open event)
    event CrossChainDepositIntent(
        address indexed depositor,
        uint256 indexed precommitment,
        uint256 amount,
        uint256 destinationChainId,
        bytes32 indexed orderId
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when deposit amount is zero
    error InvalidAmount();

    /// @notice Thrown when ShinobiInputSettler is not configured
    error InputSettlerNotSet();

    /// @notice Thrown when destination chain configuration is not set
    error ConfigurationNotSet();

    /// @notice Thrown when setter is called with zero address
    error InvalidAddress();

    /// @notice Thrown when chain ID is zero
    error InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit funds for cross-chain transfer to pool
     * @dev User-friendly function that handles all complexity internally
     * @param precommitment The precommitment for the pool deposit
     */
    function deposit(uint256 precommitment) external payable nonReentrant {
        if (msg.value == 0) revert InvalidAmount();
        if (inputSettler == address(0)) revert InputSettlerNotSet();
        if (destinationChainId == 0) revert ConfigurationNotSet();

        // Generate global unique nonce
        uint256 intentNonce = ++nonce;

        // Calculate deadlines
        uint32 fillDeadline = uint32(block.timestamp) + defaultFillDeadline;
        uint32 expires = uint32(block.timestamp) + defaultExpiry;

        // Empty refund calldata = simple refund to user
        bytes memory refundCalldata = "";

        // Construct input (native ETH)
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), msg.value];

        // CRITICAL: Construct output.call with VERIFIED depositor (msg.sender)
        bytes memory outputCall = abi.encodeWithSignature(
            "processCrossChainDeposit(address,uint256,uint256)",
            msg.sender,  // VERIFIED depositor
            msg.value,
            precommitment
        );

        // Construct output for destination chain
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destinationOracle))),
            settler: bytes32(uint256(uint160(destinationOutputSettler))),  // Output Settler
            chainId: destinationChainId,
            token: bytes32(0), // Native ETH
            amount: msg.value,
            recipient: bytes32(uint256(uint160(destinationEntrypoint))),  // Entrypoint receives the callback
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

        // Calculate orderId for event emission using library (gas efficient)
        bytes32 orderId = intent.orderIdentifier();

        // Emit event for indexers to track deposit initiation
        emit CrossChainDepositIntent(
            msg.sender,
            precommitment,
            msg.value,
            destinationChainId,
            orderId
        );

        // Call ShinobiInputSettler to open intent and escrow funds
        // ShinobiInputSettler will emit Open(orderId, intent) event
        IShinobiInputSettler(inputSettler).open{value: msg.value}(intent);
    }

    /**
     * @notice Request refund for expired deposit
     * @dev Can be called by anyone after intent expiry
     * @dev Funds are always sent to intent.user, not the caller
     * @param intent The original deposit intent
     */
    function refund(ShinobiIntent calldata intent) external nonReentrant {
        if (inputSettler == address(0)) revert InputSettlerNotSet();

        // Call ShinobiInputSettler to process refund
        // Funds will be sent to intent.user regardless of caller
        // ShinobiInputSettler will emit Refunded(orderId) event
        IShinobiInputSettler(inputSettler).refund(intent);
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the ShinobiInputSettler address
     * @param _inputSettler Address of the ShinobiInputSettler contract
     */
    function setInputSettler(address _inputSettler) external onlyOwner {
        if (_inputSettler == address(0)) revert InvalidAddress();
        address previousInputSettler = inputSettler;
        inputSettler = _inputSettler;
        emit InputSettlerUpdated(previousInputSettler, _inputSettler);
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
        if (_chainId == 0) revert InvalidChainId();
        if (_entrypoint == address(0)) revert InvalidAddress();
        if (_outputSettler == address(0)) revert InvalidAddress();
        if (_oracle == address(0)) revert InvalidAddress();

        // Update destination chain configuration
        destinationChainId = _chainId;
        destinationEntrypoint = _entrypoint;
        destinationOutputSettler = _outputSettler;
        destinationOracle = _oracle;

        emit DestinationConfigUpdated(_chainId, _entrypoint, _outputSettler, _oracle);
    }
}
