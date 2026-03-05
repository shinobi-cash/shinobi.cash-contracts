// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrosschainWithdraw2ProofLib
 * @notice Groth16 proof signal extraction for cross-chain 2:1 withdrawals (12 signals)
 * @dev Public signals order:
 *      [0] newCommitment     - Output: change commitment
 *      [1] nullifierHash0        - Output: first spent nullifier
 *      [2] nullifierHash1        - Output: second spent nullifier
 *      [3] refundCommitment  - Output: commitment for refund (with netRefundAmount)
 *      [4] relayFeeBPSOut        - Output: relay fee in basis points
 *      [5] refundFeeBPSOut       - Output: refund fee in basis points
 *      [6] withdrawnValue        - Input: amount withdrawn
 *      [7] stateRoot             - Input: merkle state root
 *      [8] stateTreeDepth        - Input: state tree depth
 *      [9] ASPRoot               - Input: ASP merkle root
 *      [10] ASPTreeDepth         - Input: ASP tree depth
 *      [11] context              - Input: binding context hash
 */
library CrosschainWithdraw2ProofLib {

    struct CrosschainWithdraw2Proof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[12] pubSignals;
    }

    function newCommitment(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function nullifierHash0(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function nullifierHash1(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function refundCommitment(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function relayFeeBPS(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function refundFeeBPS(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function withdrawnValue(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function stateRoot(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function stateTreeDepth(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }

    function ASPRoot(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[9];
    }

    function ASPTreeDepth(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[10];
    }

    function context(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[11];
    }
}
