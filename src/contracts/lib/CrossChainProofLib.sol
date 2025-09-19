// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title CrossChainProofLib
 * @notice Facilitates accessing the public signals of a Groth16 proof for cross-chain withdrawals.
 * @dev Extends ProofLib pattern with 9th public signal for refund commitment hash
 */
library CrossChainProofLib {
    /*///////////////////////////////////////////////////////////////
                     CROSS-CHAIN WITHDRAWAL PROOF 
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Struct containing Groth16 proof elements and public signals for cross-chain withdrawal verification
     * @dev The public signals array must match the order of public inputs/outputs in the circuit
     * @param pA First elliptic curve point (π_A) of the Groth16 proof, encoded as two field elements
     * @param pB Second elliptic curve point (π_B) of the Groth16 proof, encoded as 2x2 matrix of field elements
     * @param pC Third elliptic curve point (π_C) of the Groth16 proof, encoded as two field elements
     * @param pubSignals Array of public inputs and outputs (identical to standard + 1 extra):
     *        - [0] newCommitmentHash: Hash of the new commitment being created
     *        - [1] existingNullifierHash: Hash of the nullifier being spent
     *        - [2] withdrawnValue: Amount being withdrawn
     *        - [3] stateRoot: Current state root of the privacy pool
     *        - [4] stateTreeDepth: Current depth of the state tree
     *        - [5] ASPRoot: Current root of the Association Set Provider tree
     *        - [6] ASPTreeDepth: Current depth of the ASP tree
     *        - [7] context: Context value for the withdrawal operation
     *        - [8] refundCommitmentHash: Hash of commitment for refund recovery (NEW)
     */
    struct CrossChainWithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[9] pubSignals;
    }

    /*///////////////////////////////////////////////////////////////
                        STANDARD SIGNAL EXTRACTORS (0-7)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the new commitment hash from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The hash of the new commitment being created
     */
    function newCommitmentHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    /**
     * @notice Retrieves the existing nullifier hash from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The hash of the nullifier being spent in this withdrawal
     */
    function existingNullifierHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    /**
     * @notice Retrieves the withdrawn value from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The amount being withdrawn from Privacy Pool
     */
    function withdrawnValue(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    /**
     * @notice Retrieves the state root from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The root of the state tree at time of proof generation
     */
    function stateRoot(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    /**
     * @notice Retrieves the state tree depth from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The depth of the state tree at time of proof generation
     */
    function stateTreeDepth(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    /**
     * @notice Retrieves the ASP root from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The latest root of the ASP tree at time of proof generation
     */
    function ASPRoot(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    /**
     * @notice Retrieves the ASP tree depth from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The depth of the ASP tree at time of proof generation
     */
    function ASPTreeDepth(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    /**
     * @notice Retrieves the context value from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The context value binding the proof to specific withdrawal data
     */
    function context(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    /*///////////////////////////////////////////////////////////////
                     CROSS-CHAIN SPECIFIC SIGNAL EXTRACTOR (8)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the refund commitment hash from the proof's public signals
     * @dev This is the 9th signal (index 8), unique to cross-chain withdrawals
     * @param _p The proof containing the public signals
     * @return The hash of the commitment for refund recovery in case of failed cross-chain execution
     */
    function refundCommitmentHash(CrossChainWithdrawProof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }
}