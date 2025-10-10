// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../lib/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title ShinobiInputSettler
 * @notice Unified input settler for both cross-chain withdrawals and deposits
 * @dev Handles intent creation on origin chain (where funds originate)
 * @dev For withdrawals: origin = pool chain (Ethereum)
 * @dev For deposits: origin = user's chain (e.g., Arbitrum)
 * @dev Escrows funds and releases to solver after fill proof validation
 */
contract ShinobiInputSettler is IShinobiInputSettler {
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Order status enum
    enum OrderStatus {
        None,
        Deposited,
        Claimed,
        Refunded
    }

    /// @notice Mapping from order ID to order status
    mapping(bytes32 => OrderStatus) public orderStatus;

    /// @notice Address of the entrypoint (only caller allowed for open)
    /// @dev For withdrawals: ShinobiCashEntrypoint
    /// @dev For deposits: ShinobiCrosschainDepositEntrypoint
    address public entrypoint;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidOrderStatus();
    error InvalidAmount();
    error InvalidChain();
    error TimestampPassed();
    error TimestampNotPassed();
    error RefundExecutionFailed();
    error UnauthorizedCaller();
    error ReentrancyDetected();
    error InvalidAsset();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open an intent and escrow funds
     * @dev CRITICAL: Can only be called by configured entrypoint
     * @dev The entrypoint constructs the intent with verified user context
     * @param intent The intent from the entrypoint
     */
    function open(ShinobiIntent calldata intent) external payable override {
        // CRITICAL: Only entrypoint can call this
        if (msg.sender != entrypoint) revert UnauthorizedCaller();

        // Validate intent structure
        _validateIntent(intent);

        bytes32 orderId = orderIdentifier(intent);

        // Check order doesn't exist
        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();

        // Mark as deposited BEFORE collecting funds (reentrancy protection)
        orderStatus[orderId] = OrderStatus.Deposited;

        // Collect and validate native ETH inputs
        _collectInputs(intent.inputs);

        // Validate no reentrancy
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        // ETH is now escrowed in this contract
        emit Open(orderId, intent);
    }

    /**
     * @notice Finalize intent after solver fills on destination
     * @dev Validates fill proofs and releases escrowed ETH to solver
     * @param intent The original intent
     * @param fillProofs Array of fill proofs from destination chain
     */
    function finalise(
        ShinobiIntent calldata intent,
        bytes[] calldata fillProofs
    ) external override {
        bytes32 orderId = orderIdentifier(intent);

        // Check order is in deposited state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Validate fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert TimestampPassed();

        // Validate fill proofs via fillOracle
        _validateFillProofs(intent, fillProofs);

        // Mark as claimed
        orderStatus[orderId] = OrderStatus.Claimed;

        // Extract solver address from first fill proof
        bytes32 solver = _extractSolverFromProof(fillProofs[0]);

        // Release escrowed ETH to solver
        uint256 amount = intent.inputs[0][1];
        address solverAddress = address(uint160(uint256(solver)));
        (bool success, ) = solverAddress.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Finalised(orderId, solver, solver);
    }

    /**
     * @notice Refund expired intent
     * @dev Can be called by anyone after intent expiry
     * @dev Funds are always sent to intent.user, not the caller
     * @param intent The original intent
     */
    function refund(
        ShinobiIntent calldata intent
    ) external override {
        bytes32 orderId = orderIdentifier(intent);

        // Check order is in deposited state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Validate expiry has passed
        if (block.timestamp <= intent.expires) revert TimestampNotPassed();

        // Mark as refunded (intent validated via orderIdentifier match)
        orderStatus[orderId] = OrderStatus.Refunded;

        uint256 totalAmount = _calculateTotalAmount(intent.inputs);

        if (intent.refundCalldata.length == 0) {
            // Simple refund: transfer ETH back to user
            (bool success, ) = intent.user.call{value: totalAmount}("");
            if (!success) revert RefundExecutionFailed();
        } else {
            // Custom refund: execute calldata
            (address target, bytes memory functionCalldata) = abi.decode(
                intent.refundCalldata,
                (address, bytes)
            );

            (bool success, ) = target.call{value: totalAmount}(functionCalldata);
            if (!success) revert RefundExecutionFailed();
        }

        emit Refunded(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate total amount from inputs
     * @param inputs Array of input tokens [address, amount]
     */
    function _calculateTotalAmount(uint256[2][] calldata inputs) internal pure returns (uint256 totalAmount) {
        for (uint256 i = 0; i < inputs.length; i++) {
            totalAmount += inputs[i][1];
        }
    }

    /**
     * @notice Collect and validate native ETH inputs
     * @param inputs Array of input tokens [address, amount]
     */
    function _collectInputs(uint256[2][] calldata inputs) internal {
        if (inputs.length == 0) revert InvalidAmount();

        uint256 expectedEthValue = 0;

        for (uint256 i = 0; i < inputs.length; i++) {
            uint256 assetId = inputs[i][0];
            uint256 amount = inputs[i][1];

            // Only native ETH (zero address) is supported
            if (assetId != 0) revert InvalidAsset();

            expectedEthValue += amount;
        }

        // Verify sufficient ETH was sent
        if (msg.value < expectedEthValue) revert InvalidAmount();

        // ETH is now escrowed in this contract
    }

    function _validateIntent(ShinobiIntent calldata intent) internal view {
        // Validate origin chain
        if (intent.originChainId != block.chainid) revert InvalidChain();

        // Validate deadlines
        if (block.timestamp >= intent.fillDeadline) revert TimestampPassed();
        if (block.timestamp >= intent.expires) revert TimestampPassed();
        if (intent.expires <= intent.fillDeadline) revert TimestampPassed();

        // Validate has inputs
        if (intent.inputs.length == 0) revert InvalidAmount();

        // Validate has outputs
        if (intent.outputs.length == 0) revert InvalidAmount();
    }

    function _validateFillProofs(
        ShinobiIntent calldata intent,
        bytes[] calldata fillProofs
    ) internal view {
        // Validate we have proofs for all outputs
        require(fillProofs.length == intent.outputs.length, "Invalid proof count");

        // Build proof series for oracle validation
        bytes memory proofSeries = new bytes(128 * intent.outputs.length);

        for (uint256 i = 0; i < intent.outputs.length; i++) {
            // Each proof should be: remoteChainId, remoteOracle, application, dataHash
            bytes32 remoteChainId = bytes32(intent.outputs[i].chainId);
            bytes32 remoteOracle = intent.outputs[i].oracle;
            bytes32 application = intent.outputs[i].settler;
            bytes32 dataHash = keccak256(fillProofs[i]);

            // Pack into proof series
            assembly {
                let offset := add(proofSeries, add(32, mul(i, 128)))
                mstore(offset, remoteChainId)
                mstore(add(offset, 32), remoteOracle)
                mstore(add(offset, 64), application)
                mstore(add(offset, 96), dataHash)
            }
        }

        // Validate via fill oracle
        IInputOracle(intent.fillOracle).efficientRequireProven(proofSeries);
    }

    function _extractSolverFromProof(bytes calldata proof) internal pure returns (bytes32 solver) {
        // Fill proof format: solver(32) | orderId(32) | timestamp(4) | ...
        assembly {
            solver := calldataload(proof.offset)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function orderIdentifier(ShinobiIntent memory intent) public pure override returns (bytes32) {
        return intent.orderIdentifier();
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the entrypoint address
     * @dev Can only be called once during deployment setup
     * @dev NOTE: In production, add access control or pass in constructor
     * @param _entrypoint Address of the entrypoint contract
     */
    function setEntrypoint(address _entrypoint) external {
        require(entrypoint == address(0), "Entrypoint already set");
        require(_entrypoint != address(0), "Invalid address");
        entrypoint = _entrypoint;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
