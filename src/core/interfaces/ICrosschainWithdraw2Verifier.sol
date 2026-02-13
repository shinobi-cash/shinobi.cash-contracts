// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title ICrosschainWithdraw2Verifier
 * @notice Interface for verifying cross-chain Withdraw2 (2 inputs -> 1 output) Groth16 proofs
 * @dev Verifies proofs for combining 2 input notes into 1 output note (change) with withdrawal.
 *      Cross-chain version includes refundCommitmentHash for recovery (14 signals).
 */
interface ICrosschainWithdraw2Verifier {
    /**
     * @notice Verifies a cross-chain Withdraw2 Groth16 proof
     * @param _pA First elliptic curve point (pi_A) of the Groth16 proof
     * @param _pB Second elliptic curve point (pi_B) of the Groth16 proof
     * @param _pC Third elliptic curve point (pi_C) of the Groth16 proof
     * @param _pubSignals Array of 14 public signals:
     *        [0] newCommitmentHash    - Change output commitment
     *        [1] nullifierHash0       - Input 0 nullifier (spent)
     *        [2] nullifierHash1       - Input 1 nullifier (spent)
     *        [3] refundCommitmentHash - Cross-chain refund commitment
     *        [4] relayFeeBPSOut       - Relay fee in basis points
     *        [5] refundFeeBPSOut      - Refund fee in basis points
     *        [6] withdrawnValue       - Amount withdrawn
     *        [7] stateRoot            - State merkle root
     *        [8] stateTreeDepth       - State tree depth
     *        [9] ASPRoot              - ASP merkle root
     *        [10] ASPTreeDepth        - ASP tree depth
     *        [11] context             - Binding context hash
     *        [12] relayFeeBPS         - Relay fee input
     *        [13] refundFeeBPS        - Refund fee input
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[14] calldata _pubSignals
    ) external view returns (bool);
}
