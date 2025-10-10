// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/types/ShinobiIntentType.sol";
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
    address public destinationOracle;

    /// @notice Global nonce for generating unique order IDs
    uint256 public nonce;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    // No events needed - ShinobiInputSettler emits Open/Refunded events

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error InputSettlerNotSet();
    error ConfigurationNotSet();

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
            "crossChainDeposit(address,uint256,uint256)",
            msg.sender,  // VERIFIED depositor
            msg.value,
            precommitment
        );

        // Construct output for destination chain
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destinationOracle))),
            settler: bytes32(uint256(uint160(destinationEntrypoint))),
            chainId: destinationChainId,
            token: bytes32(0), // Native ETH
            amount: msg.value,
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
        require(_inputSettler != address(0), "Invalid address");
        inputSettler = _inputSettler;
    }

    /**
     * @notice Set default fill deadline duration
     * @param _fillDeadline Fill deadline in seconds from now
     */
    function setDefaultFillDeadline(uint32 _fillDeadline) external onlyOwner {
        defaultFillDeadline = _fillDeadline;
    }

    /**
     * @notice Set default expiry duration
     * @param _expiry Expiry in seconds from now
     */
    function setDefaultExpiry(uint32 _expiry) external onlyOwner {
        defaultExpiry = _expiry;
    }

    /**
     * @notice Set fill oracle address
     * @param _fillOracle Fill oracle address
     */
    function setFillOracle(address _fillOracle) external onlyOwner {
        fillOracle = _fillOracle;
    }

    /**
     * @notice Set intent oracle address
     * @param _intentOracle Intent oracle address
     */
    function setIntentOracle(address _intentOracle) external onlyOwner {
        intentOracle = _intentOracle;
    }

    /**
     * @notice Set destination chain configuration
     * @param _chainId Destination chain ID (where pool is deployed)
     * @param _entrypoint Destination ShinobiCashEntrypoint address
     * @param _oracle Destination oracle address
     */
    function setDestinationConfig(
        uint256 _chainId,
        address _entrypoint,
        address _oracle
    ) external onlyOwner {
        require(_chainId != 0, "Invalid chain ID");
        require(_entrypoint != address(0), "Invalid entrypoint");
        require(_oracle != address(0), "Invalid oracle");

        destinationChainId = _chainId;
        destinationEntrypoint = _entrypoint;
        destinationOracle = _oracle;
    }
}
