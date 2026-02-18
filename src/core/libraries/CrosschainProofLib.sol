// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrosschainProofLib
 * @notice Groth16 proof signal extraction for cross-chain 1:1 withdrawals (11 signals)
 * @dev Public signals order:
 *      [0] newCommitmentHash    - Output: new commitment after withdrawal
 *      [1] existingNullifierHash - Output: spent nullifier
 *      [2] refundCommitmentHash - Output: commitment for refund (with netRefundAmount)
 *      [3] relayFeeBPSOut       - Output: relay fee in basis points
 *      [4] refundFeeBPSOut      - Output: refund fee in basis points
 *      [5] withdrawnValue       - Input: amount withdrawn
 *      [6] stateRoot            - Input: merkle state root
 *      [7] stateTreeDepth       - Input: state tree depth
 *      [8] ASPRoot              - Input: ASP merkle root
 *      [9] ASPTreeDepth         - Input: ASP tree depth
 *      [10] context             - Input: binding context hash
 */
library CrosschainProofLib {

    struct CrosschainWithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[11] pubSignals;
    }

    function newCommitmentHash(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function existingNullifierHash(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function refundCommitmentHash(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function relayFeeBPS(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function refundFeeBPS(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function withdrawnValue(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function stateRoot(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function stateTreeDepth(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function ASPRoot(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }

    function ASPTreeDepth(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[9];
    }

    function context(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[10];
    }
}