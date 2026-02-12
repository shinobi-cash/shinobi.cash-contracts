// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrosschainProofLib
 * @notice Groth16 proof signal extraction for cross-chain 1:1 withdrawals (9 signals)
 * @dev Public signals: [newCommitment, nullifier, refundCommitment, withdrawnValue,
 *      stateRoot, stateTreeDepth, ASPRoot, ASPTreeDepth, context]
 */
library CrosschainProofLib {

    struct CrosschainWithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[9] pubSignals;
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

    function withdrawnValue(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function stateRoot(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function stateTreeDepth(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function ASPRoot(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function ASPTreeDepth(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    function context(CrosschainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }
}