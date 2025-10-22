// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title ICrossChainWithdrawalProofVerifier
 * @notice Interface for verifying enhanced cross-chain withdrawal ZK proofs
 * @dev This interface will be implemented by the generated Groth16 verifier contract
 *      for the enhanced circuit with 9 public signals (including refundCommitmentHash)
 */
interface ICrossChainWithdrawalProofVerifier {
    /**
     * @notice Verify a cross-chain withdrawal proof
     * @dev Verifies the Groth16 proof with enhanced 9 public signals
     * @param a Proof component A
     * @param b Proof component B  
     * @param c Proof component C
     * @param input Array of 9 public signals:
     *              [0] merkleRoot - The merkle root of the privacy pool
     *              [1] nullifier - The nullifier to prevent double spending
     *              [2] commitmentHash - The commitment being spent
     *              [3] recipient - The withdrawal recipient (same-chain or cross-chain)
     *              [4] relayer - The relayer address
     *              [5] fee - The relay fee amount
     *              [6] refund - The refund amount (for failed cross-chain intents)
     *              [7] associationSetRoot - The association set root for compliance
     *              [8] refundCommitmentHash - NEW: Hash of commitment for refund recovery
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[9] memory input
    ) external view returns (bool);
}