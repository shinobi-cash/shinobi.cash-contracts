// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {IRagequitVerifier} from "../../verifiers/interfaces/IRagequitVerifier.sol";
import {RagequitProofLib} from "../../proofLibs/RagequitProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "../FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title RagequitAction - Emergency withdrawal by original depositor
contract RagequitAction is FacetBase, IFacet {
    using RagequitProofLib for RagequitProofLib.RagequitProof;
    using InternalLeanIMT for LeanIMTData;

    IRagequitVerifier public immutable RAGEQUIT_VERIFIER;

    event Ragequit(address indexed ragequitter, uint256 commitment, uint256 label, uint256 value);

    error OnlyOriginalDepositor();
    error InvalidProof();
    error InvalidCommitment();

    constructor(IRagequitVerifier ragequitVerifier) {
        RAGEQUIT_VERIFIER = ragequitVerifier;
    }

    /// @notice Emergency withdrawal for original depositors
    function ragequit(RagequitProofLib.RagequitProof calldata proof) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        // Only original depositor can ragequit
        if (s.depositors[proof.label()] != msg.sender) revert OnlyOriginalDepositor();

        // Spend nullifier early (cheap check before expensive proof verification)
        PoolOps.spend(s, proof.nullifierHash());

        // Verify proof
        if (!RAGEQUIT_VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // Check commitment exists in tree
        if (!s.merkleTree._has(proof.commitmentHash())) revert InvalidCommitment();

        // Emit event before external call (CEI)
        emit Ragequit(msg.sender, proof.commitmentHash(), proof.label(), proof.value());

        // Balance invariant: pool should not lose more than proof.value()
        uint256 balanceBefore = address(this).balance;
        PoolOps.transferETH(msg.sender, proof.value());
        if (balanceBefore - address(this).balance > proof.value()) revert PoolOps.InvalidPoolState();
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.ragequit.selector);
    }
}
