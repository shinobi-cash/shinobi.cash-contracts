// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title ICrosschainWithdrawalProofVerifier
 * @notice Interface for verifying cross-chain withdrawal (1:1) ZK proofs
 * @dev Verifies Groth16 proofs with 11 public signals for cross-chain withdrawals
 */
interface ICrosschainWithdrawalProofVerifier {
    /**
     * @notice Verify a cross-chain withdrawal proof
     * @dev Verifies the Groth16 proof with 11 public signals
     * @param a Proof component A (pi_A)
     * @param b Proof component B (pi_B)
     * @param c Proof component C (pi_C)
     * @param input Array of 11 public signals:
     *              [0] newCommitment - Hash of the new commitment (change)
     *              [1] existingNullifierHash - Hash of the nullifier being spent
     *              [2] refundCommitment - Hash of commitment for refund recovery
     *              [3] relayFeeBPSOut - Relay fee in basis points
     *              [4] refundFeeBPSOut - Refund fee in basis points
     *              [5] withdrawnValue - Amount being withdrawn
     *              [6] stateRoot - State merkle root
     *              [7] stateTreeDepth - State tree depth
     *              [8] ASPRoot - ASP merkle root
     *              [9] ASPTreeDepth - ASP tree depth
     *              [10] context - Binding context hash
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[11] memory input
    ) external view returns (bool);
}