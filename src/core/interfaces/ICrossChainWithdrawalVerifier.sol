// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

/**
 * @title ICrossChainWithdrawalVerifier
 * @notice Interface for Cross-Chain Withdrawal ZK Proof Verifier
 * @dev Verifies Groth16 proofs for cross-chain privacy pool withdrawals with 9 public signals
 */
interface ICrossChainWithdrawalVerifier {
    /**
     * @notice Verify a cross-chain withdrawal proof
     * @param _pA Proof point A (G1)
     * @param _pB Proof point B (G2) 
     * @param _pC Proof point C (G1)
     * @param _pubSignals Array of 9 public signals:
     *   [0] newCommitmentHash - Hash of new commitment (output)
     *   [1] existingNullifierHash - Hash of existing nullifier (output)
     *   [2] refundCommitmentHash - Hash of refund commitment (output) 
     *   [3] withdrawnValue - Value being withdrawn (input)
     *   [4] stateRoot - Known state root (input)
     *   [5] stateTreeDepth - Current state tree depth (input)
     *   [6] ASPRoot - Latest ASP root (input)
     *   [7] ASPTreeDepth - Current ASP tree depth (input)
     *   [8] context - keccak256(IPrivacyPool.Withdrawal, scope) % SNARK_SCALAR_FIELD (input)
     * @return True if proof is valid, false otherwise
     */
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB, 
        uint[2] calldata _pC,
        uint[9] calldata _pubSignals
    ) external view returns (bool);
}