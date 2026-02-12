// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title ICrosschainWithdrawalProofVerifier
 * @notice Interface for verifying cross-chain withdrawal (1:1) ZK proofs
 * @dev Verifies Groth16 proofs with 9 public signals for cross-chain withdrawals
 */
interface ICrosschainWithdrawalProofVerifier {
    /**
     * @notice Verify a cross-chain withdrawal proof
     * @dev Verifies the Groth16 proof with 9 public signals
     * @param a Proof component A (pi_A)
     * @param b Proof component B (pi_B)
     * @param c Proof component C (pi_C)
     * @param input Array of 9 public signals:
     *              [0] newCommitmentHash - Hash of the new commitment (change)
     *              [1] existingNullifierHash - Hash of the nullifier being spent
     *              [2] refundCommitmentHash - Hash of commitment for refund recovery
     *              [3] withdrawnValue - Amount being withdrawn
     *              [4] stateRoot - State merkle root
     *              [5] stateTreeDepth - State tree depth
     *              [6] ASPRoot - ASP merkle root
     *              [7] ASPTreeDepth - ASP tree depth
     *              [8] context - Binding context hash
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[9] memory input
    ) external view returns (bool);
}