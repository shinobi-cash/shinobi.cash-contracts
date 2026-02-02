// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title IWithdraw2SameChainVerifier
 * @notice Interface for verifying same-chain Withdraw2 (2 inputs -> 1 output) Groth16 proofs
 * @dev Verifies proofs for combining 2 input notes into 1 output note (change) with withdrawal
 *      Same-chain version does NOT include refundCommitmentHash (9 signals vs 10 for cross-chain)
 */
interface IWithdraw2SameChainVerifier {
    /**
     * @notice Verifies a same-chain Withdraw2 Groth16 proof
     * @param _pA First elliptic curve point (pi_A) of the Groth16 proof
     * @param _pB Second elliptic curve point (pi_B) of the Groth16 proof
     * @param _pC Third elliptic curve point (pi_C) of the Groth16 proof
     * @param _pubSignals Array of 9 public signals:
     *        [0] newCommitmentHash    - Change output commitment
     *        [1] nullifierHash0       - Input 0 nullifier (spent)
     *        [2] nullifierHash1       - Input 1 nullifier (spent)
     *        [3] withdrawnValue       - Amount withdrawn
     *        [4] stateRoot            - State merkle root
     *        [5] stateTreeDepth       - State tree depth
     *        [6] ASPRoot              - ASP merkle root
     *        [7] ASPTreeDepth         - ASP tree depth
     *        [8] context              - Binding context hash
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[9] calldata _pubSignals
    ) external view returns (bool);
}
