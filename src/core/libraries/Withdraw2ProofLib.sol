// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

/**
 * @title Withdraw2ProofLib
 * @notice Facilitates accessing the public signals of a Groth16 proof for 2-input withdrawals.
 * @dev Withdraw2 allows combining 2 input notes into 1 output note (change) with withdrawal.
 *      Optimized for withdrawal use case where user combines deposits and withdraws to an address.
 */
library Withdraw2ProofLib {
    /*///////////////////////////////////////////////////////////////
                         WITHDRAW2 PROOF (2 inputs -> 1 output)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Struct containing Groth16 proof elements and public signals for Withdraw2 verification
     * @dev The public signals array must match the order of public inputs/outputs in the circuit
     * @param pA First elliptic curve point (pi_A) of the Groth16 proof, encoded as two field elements
     * @param pB Second elliptic curve point (pi_B) of the Groth16 proof, encoded as 2x2 matrix of field elements
     * @param pC Third elliptic curve point (pi_C) of the Groth16 proof, encoded as two field elements
     * @param pubSignals Array of public inputs and outputs (actual circuit order):
     *        - [0] newCommitmentHash: Hash of change commitment (output)
     *        - [1] nullifierHash0: Hash of input 0 nullifier being spent (output)
     *        - [2] nullifierHash1: Hash of input 1 nullifier being spent (output)
     *        - [3] refundCommitmentHash: Hash of commitment for refund recovery (output)
     *        - [4] withdrawnValue: Amount being withdrawn from pool (input)
     *        - [5] stateRoot: Current state root of the privacy pool (input)
     *        - [6] stateTreeDepth: Current depth of the state tree (input)
     *        - [7] ASPRoot: Current root of the Association Set Provider tree (input)
     *        - [8] ASPTreeDepth: Current depth of the ASP tree (input)
     *        - [9] context: Context value for the withdrawal operation (input)
     */
    struct Withdraw2Proof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[10] pubSignals;
    }

    /*///////////////////////////////////////////////////////////////
                        OUTPUT COMMITMENT EXTRACTOR (0)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the change commitment hash from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The hash of the change commitment
     */
    function newCommitmentHash(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[0];
    }

    /*///////////////////////////////////////////////////////////////
                        NULLIFIER HASH EXTRACTORS (1-2)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the first input nullifier hash from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The hash of input 0 nullifier being spent
     */
    function nullifierHash0(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[1];
    }

    /**
     * @notice Retrieves the second input nullifier hash from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The hash of input 1 nullifier being spent
     */
    function nullifierHash1(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[2];
    }

    /*///////////////////////////////////////////////////////////////
                     CROSS-CHAIN REFUND EXTRACTOR (3)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the refund commitment hash from the proof's public signals
     * @dev Used for cross-chain recovery if the intent fails
     * @param _p The proof containing the public signals
     * @return The hash of the commitment for refund recovery
     */
    function refundCommitmentHash(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[3];
    }

    /*///////////////////////////////////////////////////////////////
                        WITHDRAWAL VALUE EXTRACTOR (4)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the withdrawn value from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The amount being withdrawn from Privacy Pool
     */
    function withdrawnValue(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[4];
    }

    /*///////////////////////////////////////////////////////////////
                        STATE TREE EXTRACTORS (5-6)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the state root from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The root of the state tree at time of proof generation
     */
    function stateRoot(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[5];
    }

    /**
     * @notice Retrieves the state tree depth from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The depth of the state tree at time of proof generation
     */
    function stateTreeDepth(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[6];
    }

    /*///////////////////////////////////////////////////////////////
                        ASP TREE EXTRACTORS (7-8)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the ASP root from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The latest root of the ASP tree at time of proof generation
     */
    function ASPRoot(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[7];
    }

    /**
     * @notice Retrieves the ASP tree depth from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The depth of the ASP tree at time of proof generation
     */
    function ASPTreeDepth(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[8];
    }

    /*///////////////////////////////////////////////////////////////
                        CONTEXT EXTRACTOR (9)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the context value from the proof's public signals
     * @param _p The proof containing the public signals
     * @return The context value binding the proof to specific withdrawal data
     */
    function context(Withdraw2Proof memory _p) internal pure returns (uint256) {
        return _p.pubSignals[9];
    }
}
