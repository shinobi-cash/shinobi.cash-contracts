// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVerifier} from "interfaces/IVerifier.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title WithdrawFacet - Same-chain 1:1 withdrawal
contract WithdrawFacet is FacetBase, IFacet {
    using ProofLib for ProofLib.WithdrawProof;

    IVerifier public immutable WITHDRAWAL_VERIFIER;

    event Withdrawn(address indexed processooor, uint256 value, uint256 spentNullifier, uint256 newCommitment);
    event WithdrawalRelayed(
        address indexed relayer, address indexed recipient, address indexed asset, uint256 amount, uint256 feeAmount
    );

    error InvalidProcessooor();
    error InvalidProof();
    error RelayFeeGreaterThanMax();

    constructor(IVerifier withdrawalVerifier) {
        WITHDRAWAL_VERIFIER = withdrawalVerifier;
    }

    /// @notice Process a same-chain withdrawal with ZK proof
    function withdraw(IPrivacyPool.Withdrawal calldata withdrawal, ProofLib.WithdrawProof calldata proof)
        external
        nonReentrant
    {
        if (withdrawal.processooor != address(this)) revert InvalidProcessooor();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        PoolStorageData storage s = PoolStorageLib.layout();

        // Validate proof
        PoolOps.validateProofContext(s, withdrawal, proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        // Verify ZK proof
        if (
            !WITHDRAWAL_VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)
        ) revert InvalidProof();

        // State updates
        PoolOps.spend(s, proof.existingNullifierHash());
        PoolOps.insert(s, proof.newCommitmentHash());

        // Decode relay data and distribute funds
        IEntrypoint.RelayData memory relayData = abi.decode(withdrawal.data, (IEntrypoint.RelayData));
        if (relayData.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        uint256 withdrawnValue = proof.withdrawnValue();
        uint256 relayFee = PoolOps.calculateFee(withdrawnValue, relayData.relayFeeBPS);
        uint256 recipientAmount = withdrawnValue - relayFee;

        PoolOps.transferETH(relayData.recipient, recipientAmount);
        if (relayFee > 0) {
            PoolOps.transferETH(relayData.feeRecipient, relayFee);
        }

        emit Withdrawn(address(this), withdrawnValue, proof.existingNullifierHash(), proof.newCommitmentHash());
        emit WithdrawalRelayed(msg.sender, relayData.recipient, s.asset, withdrawnValue, relayFee);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.withdraw.selector);
    }
}
