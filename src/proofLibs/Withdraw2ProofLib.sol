// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title Withdraw2ProofLib
 * @notice Groth16 proof signal extraction for same-chain 2:1 withdrawals (9 signals)
 * @dev Public signals: [newCommitment, nullifier0, nullifier1, withdrawnValue,
 *      stateRoot, stateTreeDepth, ASPRoot, ASPTreeDepth, context]
 */
library Withdraw2ProofLib {

    struct Withdraw2Proof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[9] pubSignals;
    }

    function newCommitment(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function nullifierHash0(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function nullifierHash1(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function withdrawnValue(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function stateRoot(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function stateTreeDepth(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function ASPRoot(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function ASPTreeDepth(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function context(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }
}
