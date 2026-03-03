// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWithdraw2Verifier} from "../../core/interfaces/IWithdraw2Verifier.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {Withdraw2ProofLib} from "../../core/libraries/Withdraw2ProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title Withdraw2Facet - Same-chain 2:1 merge withdrawal
contract Withdraw2Facet is FacetBase, IFacet {
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;

    IWithdraw2Verifier public immutable VERIFIER;

    struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

    event Withdraw2Relayed(
        address indexed relayer,
        address indexed recipient,
        address indexed asset,
        uint256 amount,
        uint256 feeAmount,
        Withdraw2Nullifiers nullifiers
    );

    error InvalidProcessooor();
    error InvalidProof();
    error RelayFeeGreaterThanMax();

    constructor(IWithdraw2Verifier verifier) {
        VERIFIER = verifier;
    }

    function withdraw2(IPrivacyPool.Withdrawal calldata withdrawal, Withdraw2ProofLib.Withdraw2Proof calldata proof)
        external
        nonReentrant
    {
        if (withdrawal.processooor != address(this)) revert InvalidProcessooor();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        PoolStorageData storage s = PoolStorageLib.layout();

        // ZK validation
        PoolOps.validateProofContext(s, withdrawal, proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        if (!VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // Spend both nullifiers, insert new commitment
        PoolOps.spend(s, proof.nullifierHash0());
        PoolOps.spend(s, proof.nullifierHash1());
        PoolOps.insert(s, proof.newCommitmentHash());

        // Distribute funds
        IEntrypoint.RelayData memory relayData = abi.decode(withdrawal.data, (IEntrypoint.RelayData));
        if (relayData.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        uint256 withdrawnValue = proof.withdrawnValue();
        uint256 relayFee = PoolOps.calculateFee(withdrawnValue, relayData.relayFeeBPS);
        uint256 recipientAmount = withdrawnValue - relayFee;

        PoolOps.transferETH(relayData.recipient, recipientAmount);
        if (relayFee > 0) {
            PoolOps.transferETH(relayData.feeRecipient, relayFee);
        }

        emit Withdraw2Relayed(
            msg.sender,
            relayData.recipient,
            s.asset,
            withdrawnValue,
            relayFee,
            Withdraw2Nullifiers(proof.nullifierHash0(), proof.nullifierHash1())
        );
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.withdraw2.selector);
    }
}
