// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title RagequitProofLib
 * @notice Groth16 proof signal extraction for ragequit proofs (4 signals)
 * @dev Public signals: [commitmentHash, nullifierHash, value, label]
 */
library RagequitProofLib {
    struct RagequitProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[4] pubSignals;
    }

    function commitmentHash(RagequitProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    function nullifierHash(RagequitProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    function value(RagequitProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    function label(RagequitProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }
}
