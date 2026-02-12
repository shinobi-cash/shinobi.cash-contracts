// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrosschainWithdraw2ProofLib
 * @notice Groth16 proof signal extraction for cross-chain 2:1 withdrawals (10 signals)
 * @dev Public signals: [newCommitment, nullifier0, nullifier1, refundCommitment, withdrawnValue,
 *      stateRoot, stateTreeDepth, ASPRoot, ASPTreeDepth, context]
 */
library CrosschainWithdraw2ProofLib {

    struct CrosschainWithdraw2Proof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[10] pubSignals;
    }

    function newCommitmentHash(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function nullifierHash0(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function nullifierHash1(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function refundCommitmentHash(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function withdrawnValue(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function stateRoot(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function stateTreeDepth(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function ASPRoot(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function ASPTreeDepth(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }

    function context(CrosschainWithdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[9];
    }
}
