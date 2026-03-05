// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Interface for verifying ragequit Groth16 proofs (4 public signals)
interface IRagequitVerifier {
    function verifyProof(
        uint256[2] memory _pA,
        uint256[2][2] memory _pB,
        uint256[2] memory _pC,
        uint256[4] memory _pubSignals
    ) external view returns (bool);
}
