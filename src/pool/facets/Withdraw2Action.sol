// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWithdraw2Verifier} from "../../verifiers/interfaces/IWithdraw2Verifier.sol";
import {WithdrawData} from "../libraries/Types.sol";
import {Withdraw2ProofLib} from "../../proofLibs/Withdraw2ProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title Withdraw2Facet - Same-chain 2:1 merge withdrawal
contract Withdraw2Facet is FacetBase, IFacet {
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;

   struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

    IWithdraw2Verifier public immutable VERIFIER;

    event Withdraw2Relayed(
        address indexed relayer,
        address indexed recipient,
        uint256 amount,
        uint256 feeAmount,
        Withdraw2Nullifiers nullifiers,
        uint256 newCommitment
    );

    error InvalidProof();
    error RelayFeeGreaterThanMax();
    error RelayFeeBPSZero();
    error AssetConfigNotSet();

    constructor(IWithdraw2Verifier verifier) {
        VERIFIER = verifier;
    }

    function withdraw2(WithdrawData calldata data, Withdraw2ProofLib.Withdraw2Proof calldata proof)
        external
        nonReentrant
    {
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        PoolStorageData storage s = PoolStorageLib.layout();
        if (s.maxRelayFeeBPS == 0) revert AssetConfigNotSet();

        // Fee validation (cheap checks before expensive ZK verification)
        if (data.relayFeeBPS == 0) revert RelayFeeBPSZero();
        if (data.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        // ZK validation
        PoolOps.validateProofContext(s, abi.encode(data), proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        if (!VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // Spend both nullifiers, insert new commitment
        PoolOps.spend(s, proof.nullifierHash0());
        PoolOps.spend(s, proof.nullifierHash1());
        PoolOps.insert(s, proof.newCommitment());

        uint256 withdrawnValue = proof.withdrawnValue();
        uint256 relayFee = PoolOps.calculateFee(withdrawnValue, data.relayFeeBPS);
        uint256 recipientAmount = withdrawnValue - relayFee;

        // Balance invariant: pool should not lose more than withdrawnValue
        uint256 balanceBefore = address(this).balance;

        PoolOps.transferETH(data.recipient, recipientAmount);
        if (relayFee > 0) {
            PoolOps.transferETH(data.feeRecipient, relayFee);
        }

        if (balanceBefore - address(this).balance > withdrawnValue) revert PoolOps.InvalidPoolState();

        emit Withdraw2Relayed(
            msg.sender,
            data.recipient,
            withdrawnValue,
            relayFee,
            Withdraw2Nullifiers(proof.nullifierHash0(), proof.nullifierHash1()),
            proof.newCommitment()
        );
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.withdraw2.selector);
    }
}
