// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICrosschainWithdrawalProofVerifier} from "../../verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IPoolDiamond} from "../interfaces/IPoolDiamond.sol";
import {CrosschainWithdrawData} from "../libraries/Types.sol";
import {CrosschainProofLib} from "../../proofLibs/CrosschainProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";
import {IntentOps} from "../libraries/IntentOps.sol";
import {RefundOps} from "../libraries/RefundOps.sol";

bytes4 constant HANDLE_REFUND_SELECTOR = bytes4(keccak256("handleRefund(uint256,address,uint256,uint256)"));

/// @title CrosschainWithdrawFacet - Cross-chain 1:1 withdrawal with OIF intent + refund handling
contract CrosschainWithdrawFacet is FacetBase, IFacet {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;

    ICrosschainWithdrawalProofVerifier public immutable VERIFIER;

    event CrosschainWithdrawalIntentRelayed(
        address indexed relayer,
        bytes32 indexed crosschainRecipient,
        uint256 amount,
        uint256 relayFee,
        uint256 solverFee,
        bytes32 orderId,
        uint256 spentNullifier,
        uint256 newCommitment,
        uint256 refundCommitment
    );

    error InvalidProof();
    error WithdrawalInputSettlerNotSet();
    error MaxSolverFeeBPSNotSet();
    error DestinationChainNotConfigured();
    error RelayFeeGreaterThanMax();
    error RelayFeeBPSZero();
    error SolverFeeGreaterThanMax();
    error RefundFeeGreaterThanMax();
    error AssetConfigNotSet();
    error MaxRefundFeeBPSNotSet();
    error RefundFeeBPSZero();

    constructor(ICrosschainWithdrawalProofVerifier verifier) {
        VERIFIER = verifier;
    }

    function crosschainWithdraw(
        CrosschainWithdrawData calldata data,
        CrosschainProofLib.CrosschainWithdrawProof calldata proof
    ) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        if (s.withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (s.maxRelayFeeBPS == 0) revert AssetConfigNotSet();
        if (s.maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (s.maxRefundFeeBPS == 0) revert MaxRefundFeeBPSNotSet();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        uint256 destChainId = uint256(data.encodedDestination) >> 224;
        if (!s.withdrawalChainConfig[destChainId].isConfigured) revert DestinationChainNotConfigured();

        if (proof.relayFeeBPS() == 0) revert RelayFeeBPSZero();
        if (proof.relayFeeBPS() > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (data.solverFeeBPS > s.maxSolverFeeBPS) revert SolverFeeGreaterThanMax();
        if (proof.refundFeeBPS() == 0) revert RefundFeeBPSZero();
        if (proof.refundFeeBPS() > s.maxRefundFeeBPS) revert RefundFeeGreaterThanMax();

        // ZK validation
        PoolOps.validateProofContext(s, abi.encode(data), proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        if (!VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // State updates
        PoolOps.spend(s, proof.existingNullifierHash());
        PoolOps.insert(s, proof.newCommitment());

        // Create intent and emit
        uint256 balanceBefore = address(this).balance;

        IntentOps.IntentResult memory result = IntentOps.openIntent(
            s, destChainId, data,
            proof.withdrawnValue(), proof.relayFeeBPS(), proof.refundFeeBPS(),
            bytes32(proof.existingNullifierHash()), bytes32(proof.refundCommitment()),
            HANDLE_REFUND_SELECTOR
        );

        if (balanceBefore - address(this).balance > proof.withdrawnValue()) revert PoolOps.InvalidPoolState();

        emit CrosschainWithdrawalIntentRelayed(
            msg.sender, data.encodedDestination,
            result.netAmount, result.relayFee, result.solverFee, result.orderId,
            proof.existingNullifierHash(), proof.newCommitment(), proof.refundCommitment()
        );
    }

    /// @notice Handle a refund from the input settler for a failed intent
    function handleRefund(uint256 refundCommitment, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable
        nonReentrant
    {
        RefundOps.executeRefund(PoolStorageLib.layout(), refundCommitment, feeRecipient, refundFeeBPS, scope);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.crosschainWithdraw.selector, this.handleRefund.selector);
    }
}
