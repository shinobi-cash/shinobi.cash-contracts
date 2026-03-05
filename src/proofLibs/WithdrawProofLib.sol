// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title WithdrawProofLib
 * @notice Groth16 proof signal extraction for same-chain 1:1 withdrawals (8 signals)
 * @dev Public signals: [newCommitment, existingNullifierHash, withdrawnValue,
 *      stateRoot, stateTreeDepth, ASPRoot, ASPTreeDepth, context]
 */
library WithdrawProofLib {
    struct WithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[8] pubSignals;
    }

    function newCommitment(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function existingNullifierHash(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function withdrawnValue(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function stateRoot(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    function stateTreeDepth(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    function ASPRoot(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    function ASPTreeDepth(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    function context(WithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }
}
