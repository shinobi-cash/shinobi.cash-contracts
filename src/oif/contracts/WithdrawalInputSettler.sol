// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../lib/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title WithdrawalInputSettler
 * @notice Handles cross-chain withdrawal intents on origin chain (pool chain - Ethereum)
 * @dev Called by ShinobiCashEntrypoint after withdrawal from pool
 *      Escrows withdrawn ETH and releases to solver after fill proof validation
 */
contract WithdrawalInputSettler is IShinobiInputSettler {
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

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidOrderStatus();
    error InvalidAmount();
    error InvalidChain();
    error TimestampPassed();
    error TimestampNotPassed();
    error RefundExecutionFailed();
    error ReentrancyDetected();
    error InvalidAsset();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open a withdrawal intent and escrow withdrawn funds
     * @dev Called by ShinobiCashEntrypoint after user withdraws from pool
     * @param intent The withdrawal intent
     */
    function open(ShinobiIntent calldata intent) external payable override {
        // Validate intent structure
        _validateIntent(intent);

        bytes32 orderId = orderIdentifier(intent);

        // Check order doesn't exist
        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();

        // Mark as deposited BEFORE collecting funds (reentrancy protection)
        // If we can't make the deposit, we will revert and it will unmark it
        orderStatus[orderId] = OrderStatus.Deposited;

        // Collect and validate native ETH inputs
        _collectInputs(intent.inputs);

        // Validate that there has been no reentrancy
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        // ETH is now escrowed in this contract
        // All intent data is committed via orderIdentifier (includes refundCalldata)

        emit Open(orderId, intent);
    }

    /**
     * @notice Finalize withdrawal intent after solver fills on destination
     * @dev Validates fill proofs and releases escrowed ETH to solver
     * @param intent The original withdrawal intent
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

        // Validate fill proofs via inputOracle
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
     * @notice Refund expired withdrawal intent
     * @dev If refundCalldata is empty, transfers ETH to intent.user
     * @dev If refundCalldata is present, executes custom refund logic (e.g., return to pool as commitment)
     * @param intent The original withdrawal intent
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
            // encoded in chunks of 32*4=128 bytes
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
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
