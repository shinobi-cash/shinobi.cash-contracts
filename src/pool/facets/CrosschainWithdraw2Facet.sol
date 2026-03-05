// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICrosschainWithdraw2Verifier} from "../../verifiers/interfaces/ICrosschainWithdraw2Verifier.sol";
import {IPoolDiamond} from "../interfaces/IPoolDiamond.sol";
import {CrosschainWithdrawData} from "../libraries/Types.sol";
import {CrosschainWithdraw2ProofLib} from "../../proofLibs/CrosschainWithdraw2ProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";
import {IntentOps} from "../libraries/IntentOps.sol";
import {RefundOps} from "../libraries/RefundOps.sol";

bytes4 constant HANDLE_REFUND2_SELECTOR = bytes4(keccak256("handleRefund2(uint256,address,uint256,uint256)"));

/// @title CrosschainWithdraw2Facet - Cross-chain 2:1 merge withdrawal with OIF intent
contract CrosschainWithdraw2Facet is FacetBase, IFacet {
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;

    struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

    /// @dev Extracted proof data to avoid stack-too-deep
    struct ProofData {
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        uint256 refundFeeBPS;
        bytes32 refundCommitment;
        bytes32 nullifierHash0;
        bytes32 nullifierHash1;
        bytes32 newCommitment;
    }

    ICrosschainWithdraw2Verifier public immutable VERIFIER;

    event CrosschainWithdraw2IntentRelayed(
        address indexed relayer,
        bytes32 indexed crosschainRecipient,
        uint256 amount,
        uint256 relayFee,
        uint256 solverFee,
        bytes32 orderId,
        Withdraw2Nullifiers nullifiers,
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

    constructor(ICrosschainWithdraw2Verifier verifier) {
        VERIFIER = verifier;
    }

    function crosschainWithdraw2(
        CrosschainWithdrawData calldata data,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof
    ) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        if (s.withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (s.maxRelayFeeBPS == 0) revert AssetConfigNotSet();
        if (s.maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (s.maxRefundFeeBPS == 0) revert MaxRefundFeeBPSNotSet();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();

        // Extract proof data upfront to avoid stack depth issues
        ProofData memory pd = ProofData({
            withdrawnValue: proof.withdrawnValue(),
            relayFeeBPS: proof.relayFeeBPS(),
            refundFeeBPS: proof.refundFeeBPS(),
            refundCommitment: bytes32(proof.refundCommitment()),
            nullifierHash0: bytes32(proof.nullifierHash0()),
            nullifierHash1: bytes32(proof.nullifierHash1()),
            newCommitment: bytes32(proof.newCommitment())
        });

        _execute(s, data, proof, pd);
    }

    /// @notice Handle a refund from the input settler for a failed intent
    function handleRefund2(uint256 refundCommitment, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable
        nonReentrant
    {
        RefundOps.executeRefund(PoolStorageLib.layout(), refundCommitment, feeRecipient, refundFeeBPS, scope);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.crosschainWithdraw2.selector, this.handleRefund2.selector);
    }

    function _execute(
        PoolStorageData storage s,
        CrosschainWithdrawData calldata data,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof,
        ProofData memory pd
    ) internal {

        uint256 destChainId = uint256(data.encodedDestination) >> 224;
        if (!s.withdrawalChainConfig[destChainId].isConfigured) revert DestinationChainNotConfigured();

        if (pd.relayFeeBPS == 0) revert RelayFeeBPSZero();
        if (pd.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (data.solverFeeBPS > s.maxSolverFeeBPS) revert SolverFeeGreaterThanMax();
        if (pd.refundFeeBPS == 0) revert RefundFeeBPSZero();
        if (pd.refundFeeBPS > s.maxRefundFeeBPS) revert RefundFeeGreaterThanMax();

        // ZK validation
        PoolOps.validateProofContext(s, abi.encode(data), proof.context());
        PoolOps.validateTreeDepths(proof.stateTreeDepth(), proof.ASPTreeDepth());
        PoolOps.validateStateRoot(s, proof.stateRoot());
        PoolOps.validateASPRoot(s, proof.ASPRoot());

        if (!VERIFIER.verifyProof(proof.pA, proof.pB, proof.pC, proof.pubSignals)) {
            revert InvalidProof();
        }

        // State updates
        PoolOps.spend(s, uint256(pd.nullifierHash0));
        PoolOps.spend(s, uint256(pd.nullifierHash1));
        PoolOps.insert(s, uint256(pd.newCommitment));

        // Create intent and emit
        uint256 balanceBefore = address(this).balance;

        IntentOps.IntentResult memory result = IntentOps.openIntent(
            s, destChainId, data,
            pd.withdrawnValue, pd.relayFeeBPS, pd.refundFeeBPS,
            pd.nullifierHash0, pd.refundCommitment,
            HANDLE_REFUND2_SELECTOR
        );

        if (balanceBefore - address(this).balance > pd.withdrawnValue) revert PoolOps.InvalidPoolState();

        emit CrosschainWithdraw2IntentRelayed(
            msg.sender, data.encodedDestination,
            result.netAmount, result.relayFee, result.solverFee, result.orderId,
            Withdraw2Nullifiers(uint256(pd.nullifierHash0), uint256(pd.nullifierHash1)),
            uint256(pd.newCommitment), uint256(pd.refundCommitment)
        );
    }

}
