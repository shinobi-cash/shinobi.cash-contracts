// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICrosschainWithdrawalProofVerifier} from "../../core/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IShinobiCashCrosschainHandler} from "../../core/interfaces/IShinobiCashCrosschainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrosschainProofLib} from "../../core/libraries/CrosschainProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";
import {IntentOps} from "../libraries/IntentOps.sol";

/// @title CrosschainWithdrawFacet - Cross-chain 1:1 withdrawal with OIF intent + refund handling
contract CrosschainWithdrawFacet is FacetBase, IFacet {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;

    ICrosschainWithdrawalProofVerifier public immutable VERIFIER;

    event CrosschainWithdrawalIntentRelayed(
        address indexed relayer,
        bytes32 indexed crosschainRecipient,
        address indexed asset,
        uint256 amount,
        uint256 relayFee,
        uint256 solverFee,
        bytes32 orderId
    );
    event Refunded(uint256 amount, uint256 indexed refundCommitmentHash, uint256 refundFee, address indexed feeRecipient);
    event RefundCommitmentInserted(uint256 indexed refundCommitmentHash, uint256 amount);

    error InvalidProcessooor();
    error InvalidProof();
    error WithdrawalInputSettlerNotSet();
    error MaxSolverFeeBPSNotSet();
    error DestinationChainNotConfigured();
    error RelayFeeGreaterThanMax();
    error SolverFeeGreaterThanMax();
    error OnlyWithdrawalInputSettler();
    error ScopeMismatch();
    error RefundFeeTransferFailed();

    constructor(ICrosschainWithdrawalProofVerifier verifier) {
        VERIFIER = verifier;
    }

    function crosschainWithdraw(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof calldata proof
    ) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        if (s.withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (s.maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();
        if (withdrawal.processooor != address(this)) revert InvalidProcessooor();

        IShinobiCashCrosschainHandler.CrosschainRelayData memory data =
            abi.decode(withdrawal.data, (IShinobiCashCrosschainHandler.CrosschainRelayData));

        uint256 destChainId = uint256(data.encodedDestination) >> 224;
        if (!s.withdrawalChainConfig[destChainId].isConfigured) revert DestinationChainNotConfigured();

        if (proof.relayFeeBPS() > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (data.solverFeeBPS > s.maxSolverFeeBPS) revert SolverFeeGreaterThanMax();

        // ZK validation
        PoolOps.validateProofContext(s, withdrawal, proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        if (!VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // State updates
        PoolOps.spend(s, proof.existingNullifierHash());
        PoolOps.insert(s, proof.newCommitmentHash());

        // Create intent and emit
        IntentOps.IntentResult memory result = IntentOps.openIntent(
            s, destChainId, data,
            proof.withdrawnValue(), proof.relayFeeBPS(), proof.refundFeeBPS(),
            bytes32(proof.existingNullifierHash()), bytes32(proof.refundCommitmentHash())
        );

        emit CrosschainWithdrawalIntentRelayed(
            msg.sender, data.encodedDestination, s.asset,
            result.netAmount, result.relayFee, result.solverFee, result.orderId
        );
    }

    /// @notice Handle a refund from the input settler for a failed intent
    function handleRefund(uint256 refundCommitmentHash, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable
        nonReentrant
    {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (msg.sender != s.withdrawalInputSettler) revert OnlyWithdrawalInputSettler();
        if (scope != s.scope) revert ScopeMismatch();

        uint256 refundFee = PoolOps.calculateFee(msg.value, refundFeeBPS);
        uint256 refundAmount = msg.value - refundFee;

        if (refundFee > 0) {
            PoolOps.transferETH(feeRecipient, refundFee);
        }

        PoolOps.insert(s, refundCommitmentHash);

        emit RefundCommitmentInserted(refundCommitmentHash, refundAmount);
        emit Refunded(refundAmount, refundCommitmentHash, refundFee, feeRecipient);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.crosschainWithdraw.selector, this.handleRefund.selector);
    }
}
