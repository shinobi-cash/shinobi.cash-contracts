// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWithdrawalVerifier} from "../../verifiers/interfaces/IWithdrawalVerifier.sol";
import {WithdrawData} from "../libraries/Types.sol";
import {WithdrawProofLib} from "../../proofLibs/WithdrawProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "../FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title WithdrawAction - Same-chain 1:1 withdrawal
contract WithdrawAction is FacetBase, IFacet {
    using WithdrawProofLib for WithdrawProofLib.WithdrawProof;

    IWithdrawalVerifier public immutable WITHDRAWAL_VERIFIER;

    event WithdrawalRelayed(
        address indexed relayer,
        address indexed recipient,
        uint256 amount,
        uint256 feeAmount,
        uint256 spentNullifier,
        uint256 newCommitment
    );

    error InvalidProof();
    error RelayFeeGreaterThanMax();
    error RelayFeeBPSZero();
    error AssetConfigNotSet();

    constructor(IWithdrawalVerifier withdrawalVerifier) {
        WITHDRAWAL_VERIFIER = withdrawalVerifier;
    }

    /// @notice Process a same-chain withdrawal with ZK proof
    function withdraw(WithdrawData calldata data, WithdrawProofLib.WithdrawProof calldata proof)
        external
        nonReentrant
    {
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        PoolStorageData storage s = PoolStorageLib.layout();
        if (s.maxRelayFeeBPS == 0) revert AssetConfigNotSet();

        // Fee validation (cheap checks before expensive ZK verification)
        if (data.relayFeeBPS == 0) revert RelayFeeBPSZero();
        if (data.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        // Validate proof
        PoolOps.validateProofContext(s, abi.encode(data), proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        // Verify ZK proof
        if (
            !WITHDRAWAL_VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)
        ) revert InvalidProof();

        // State updates
        PoolOps.spend(s, proof.existingNullifierHash());
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

        emit WithdrawalRelayed(
            msg.sender,
            data.recipient,
            withdrawnValue,
            relayFee,
            proof.existingNullifierHash(),
            proof.newCommitment()
        );
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.withdraw.selector);
    }
}
