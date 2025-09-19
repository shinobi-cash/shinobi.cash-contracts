// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrossChainProofLib} from "../lib/CrossChainProofLib.sol";

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
     * @notice Emitted when a cross-chain withdrawal is processed
     * @param processooor The processor contract handling the cross-chain logic
     * @param withdrawnValue The amount withdrawn
     * @param existingNullifierHash The nullifier hash that was spent
     * @param newCommitmentHash The new commitment hash that was inserted
     * @param refundCommitmentHash The commitment hash for potential refunds if cross-chain intent fails
     */
    event CrossChainWithdrawalProcessed(
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
    error InvalidCrossChainWithdrawalVerifier();

    /// @notice Thrown when cross-chain proof verification fails
    error InvalidCrossChainWithdrawalProof();

    /// @notice Thrown when cross-chain proof structure is invalid
    error InvalidCrossChainWithdrawalProofStructure();

    /// @notice Thrown when cross-chain withdrawal is called by unauthorized processor
    error UnauthorizedCrossChainProcessor();

    /// @notice Thrown when the state root is invalid
    error InvalidStateRoot();

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a cross-chain withdrawal with enhanced 9-signal proof
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The enhanced 9-signal cross-chain proof
     */
    function crossChainWithdraw(
        Withdrawal memory _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory _proof
    ) external;

    /**
     * @notice Insert refund commitment into the merkle tree
     * @dev Can only be called by the entrypoint for processing refunds
     * @param _refundCommitmentHash The commitment hash to insert for refund
     * @return The updated root after insertion
     */
    function insertRefundCommitment(uint256 _refundCommitmentHash) external returns (uint256);

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the entrypoint with ETH for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund
     * @param _amount The amount being refunded (for validation)
     */
    function handleRefund(uint256 _refundCommitmentHash, uint256 _amount) external payable;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the cross-chain verifier address
     * @return The address of the cross-chain withdrawal proof verifier
     */
    function crossChainVerifier() external view returns (address);

    /**
     * @notice Check if this pool supports cross-chain withdrawals
     * @return True, as this pool supports cross-chain functionality
     */
    function supportsCrossChain() external pure returns (bool);
}