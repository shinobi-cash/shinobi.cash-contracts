// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrossChainProofLib} from "../libraries/CrossChainProofLib.sol";
import {Withdraw2ProofLib} from "../libraries/Withdraw2ProofLib.sol";
import {CrossChainWithdraw2ProofLib} from "../libraries/CrossChainWithdraw2ProofLib.sol";

/**
 * @title IShinobiCashPool
 * @notice Interface for Shinobi Cash Pool with cross-chain capabilities
 * @dev Extends IPrivacyPool with cross-chain withdrawal functionality
 */
interface IShinobiCashPool is IPrivacyPool {

    /// @notice Nullifier hashes for Withdraw2 operations
    struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

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

    /**
     * @notice Emitted when a Withdraw2 (2 inputs) is executed from the pool
     * @param processooor The processor contract handling the withdrawal
     * @param withdrawnValue The amount withdrawn
     * @param nullifiers The nullifier hashes that were spent
     * @param newCommitmentHash The change commitment hash that was inserted
     */
    event Withdraw2Executed(
        address indexed processooor,
        uint256 withdrawnValue,
        Withdraw2Nullifiers nullifiers,
        uint256 indexed newCommitmentHash
    );

    /**
     * @notice Emitted when a cross-chain Withdraw2 is executed
     * @param processooor The processor contract handling the cross-chain logic
     * @param withdrawnValue The amount withdrawn
     * @param nullifiers The nullifier hashes that were spent
     * @param newCommitmentHash The change commitment hash that was inserted
     * @param refundCommitmentHash The commitment hash for potential refunds
     */
    event CrossChainWithdraw2Executed(
        address indexed processooor,
        uint256 withdrawnValue,
        Withdraw2Nullifiers nullifiers,
        uint256 indexed newCommitmentHash,
        uint256 refundCommitmentHash
    );

     /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when cross-chain verifier address is zero
    error InvalidCrossChainWithdrawalVerifier();

    /// @notice Thrown when cross-chain proof verification fails
    error InvalidCrosschainWithdrawalProof();

    /// @notice Thrown when ETH amount doesn't match expected amount
    error AmountMismatch();

    /// @notice Thrown when same-chain Withdraw2 verifier address is zero
    error InvalidWithdraw2Verifier();

    /// @notice Thrown when cross-chain Withdraw2 verifier address is zero
    error InvalidCrossChainWithdraw2Verifier();

    /// @notice Thrown when same-chain Withdraw2 proof verification fails
    error InvalidWithdraw2Proof();

    /// @notice Thrown when cross-chain Withdraw2 proof verification fails
    error InvalidCrossChainWithdraw2Proof();

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

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW2 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a same-chain Withdraw2 combining 2 inputs into 1 output (change) with withdrawal
     * @param _withdrawal The withdrawal data
     * @param _proof The same-chain Withdraw2 9-signal proof (no refund commitment)
     */
    function withdraw2(
        Withdrawal memory _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory _proof
    ) external;

    /**
     * @notice Process a cross-chain Withdraw2
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The cross-chain Withdraw2 10-signal proof with refund commitment
     */
    function crossChainWithdraw2(
        Withdrawal memory _withdrawal,
        CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof memory _proof
    ) external;

}
