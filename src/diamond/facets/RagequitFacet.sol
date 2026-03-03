// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {IVerifier} from "interfaces/IVerifier.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title RagequitFacet - Emergency withdrawal by original depositor
contract RagequitFacet is FacetBase, IFacet {
    using ProofLib for ProofLib.RagequitProof;
    using InternalLeanIMT for LeanIMTData;

    IVerifier public immutable RAGEQUIT_VERIFIER;

    event Ragequit(address indexed ragequitter, uint256 commitment, uint256 label, uint256 value);

    error OnlyOriginalDepositor();
    error InvalidProof();
    error InvalidCommitment();

    constructor(IVerifier ragequitVerifier) {
        RAGEQUIT_VERIFIER = ragequitVerifier;
    }

    /// @notice Emergency withdrawal for original depositors
    function ragequit(ProofLib.RagequitProof calldata proof) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        // Only original depositor can ragequit
        if (s.depositors[proof.label()] != msg.sender) revert OnlyOriginalDepositor();

        // Verify proof
        if (!RAGEQUIT_VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // Check commitment exists in tree
        if (!s.merkleTree._has(proof.commitmentHash())) revert InvalidCommitment();

        // Spend nullifier
        PoolOps.spend(s, proof.nullifierHash());

        // Transfer value to depositor
        PoolOps.transferETH(msg.sender, proof.value());

        emit Ragequit(msg.sender, proof.commitmentHash(), proof.label(), proof.value());
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.ragequit.selector);
    }
}
