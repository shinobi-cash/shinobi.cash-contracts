// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title IJoinSplitVerifier
 * @notice Interface for verifying JoinSplit 2x1 Groth16 proofs
 * @dev Verifies proofs for combining 2 input notes into 1 output note (change) with withdrawal
 */
interface IJoinSplitVerifier {
    /**
     * @notice Verifies a JoinSplit 2x1 Groth16 proof
     * @param _pA First elliptic curve point (pi_A) of the Groth16 proof
     * @param _pB Second elliptic curve point (pi_B) of the Groth16 proof
     * @param _pC Third elliptic curve point (pi_C) of the Groth16 proof
     * @param _pubSignals Array of 10 public signals:
     *        [0] newCommitmentHash    - Change output commitment
     *        [1] nullifierHash0       - Input 0 nullifier (spent)
     *        [2] nullifierHash1       - Input 1 nullifier (spent)
     *        [3] refundCommitmentHash - Cross-chain refund commitment
     *        [4] withdrawnValue       - Amount withdrawn
     *        [5] stateRoot            - State merkle root
     *        [6] stateTreeDepth       - State tree depth
     *        [7] ASPRoot              - ASP merkle root
     *        [8] ASPTreeDepth         - ASP tree depth
     *        [9] context              - Binding context hash
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[10] calldata _pubSignals
    ) external view returns (bool);
}
