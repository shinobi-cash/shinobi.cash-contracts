// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrossChainProofLib
 * @notice Groth16 proof signal extraction for cross-chain 1:1 withdrawals (9 signals)
 * @dev Public signals: [newCommitment, nullifier, refundCommitment, withdrawnValue,
 *      stateRoot, stateTreeDepth, ASPRoot, ASPTreeDepth, context]
 */
library CrossChainProofLib {

    struct CrossChainWithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[9] pubSignals;
    }

    function newCommitmentHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function existingNullifierHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function refundCommitmentHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function withdrawnValue(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function stateRoot(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function stateTreeDepth(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function ASPRoot(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function ASPTreeDepth(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function context(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }
}