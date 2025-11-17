// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrossChainProofLib} from "../libraries/CrossChainProofLib.sol";

/**
 * @title IShinobiCashPool
 * @notice Interface for Shinobi Cash Pool with cross-chain capabilities
 * @dev Extends IPrivacyPool with cross-chain withdrawal functionality
 */
interface IShinobiCashPool is IPrivacyPool {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a cross-chain withdrawal is executed from the pool
     * @param processooor The processor contract handling the cross-chain logic
     * @param withdrawnValue The amount withdrawn
     * @param existingNullifierHash The nullifier hash that was spent
     * @param newCommitmentHash The new commitment hash that was inserted
     * @param refundCommitmentHash The commitment hash for potential refunds if cross-chain intent fails (cross-chain specific)
     */
    event CrosschainWithdrawn(
        address indexed processooor,
        uint256 withdrawnValue,
        uint256 indexed existingNullifierHash,
        uint256 indexed newCommitmentHash,
        uint256 refundCommitmentHash
    );

    /**
     * @notice Emitted when a refund commitment is inserted for failed cross-chain withdrawal
     * @param processoor The entrypoint that processed the refund
     * @param refundCommitmentHash The commitment hash inserted for refund
     * @param refundAmount The amount available for refund
     */
    event RefundCommitmentInserted(
        address indexed processoor,
        uint256 indexed refundCommitmentHash,
        uint256 refundAmount
    );

     /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when cross-chain verifier address is zero
    error InvalidCrosschainWithdrawalVerifier();

    /// @notice Thrown when cross-chain proof verification fails
    error InvalidCrosschainWithdrawalProof();

    /// @notice Thrown when ETH amount doesn't match expected amount
    error AmountMismatch();

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a cross-chain withdrawal with enhanced 9-signal proof
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The enhanced 9-signal cross-chain proof
     */
    function crosschainWithdraw(
        Withdrawal memory _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory _proof
    ) external;

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the entrypoint with ETH for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund
     * @param _amount The amount being refunded (for validation)
     */
    function handleRefund(uint256 _refundCommitmentHash, uint256 _amount) external payable;

}