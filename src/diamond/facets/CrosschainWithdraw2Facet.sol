// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICrosschainWithdraw2Verifier} from "../../core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {IShinobiCashCrosschainHandler} from "../../core/interfaces/IShinobiCashCrosschainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrosschainWithdraw2ProofLib} from "../../core/libraries/CrosschainWithdraw2ProofLib.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";
import {IntentOps} from "../libraries/IntentOps.sol";

/// @title CrosschainWithdraw2Facet - Cross-chain 2:1 merge withdrawal with OIF intent
contract CrosschainWithdraw2Facet is FacetBase, IFacet {
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;

    ICrosschainWithdraw2Verifier public immutable VERIFIER;

    struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

    /// @dev Extracted proof data to avoid stack-too-deep
    struct ProofData {
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        uint256 refundFeeBPS;
        bytes32 refundCommitmentHash;
        bytes32 nullifierHash0;
        bytes32 nullifierHash1;
        bytes32 newCommitmentHash;
    }

    event CrosschainWithdraw2IntentRelayed(
        address indexed relayer,
        bytes32 indexed crosschainRecipient,
        address indexed asset,
        uint256 amount,
        uint256 relayFee,
        uint256 solverFee,
        bytes32 orderId,
        Withdraw2Nullifiers nullifiers
    );

    error InvalidProcessooor();
    error InvalidProof();
    error WithdrawalInputSettlerNotSet();
    error MaxSolverFeeBPSNotSet();
    error DestinationChainNotConfigured();
    error RelayFeeGreaterThanMax();
    error SolverFeeGreaterThanMax();

    constructor(ICrosschainWithdraw2Verifier verifier) {
        VERIFIER = verifier;
    }

    function crosschainWithdraw2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof
    ) external nonReentrant {
        PoolStorageData storage s = PoolStorageLib.layout();

        if (s.withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (s.maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (proof.withdrawnValue() == 0) revert PoolOps.InvalidWithdrawalAmount();
        if (withdrawal.processooor != address(this)) revert InvalidProcessooor();

        // Extract proof data upfront to avoid stack depth issues
        ProofData memory pd = ProofData({
            withdrawnValue: proof.withdrawnValue(),
            relayFeeBPS: proof.relayFeeBPS(),
            refundFeeBPS: proof.refundFeeBPS(),
            refundCommitmentHash: bytes32(proof.refundCommitmentHash()),
            nullifierHash0: bytes32(proof.nullifierHash0()),
            nullifierHash1: bytes32(proof.nullifierHash1()),
            newCommitmentHash: bytes32(proof.newCommitmentHash())
        });

        _execute(s, withdrawal, proof, pd);
    }

    function _execute(
        PoolStorageData storage s,
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof,
        ProofData memory pd
    ) internal {
        IShinobiCashCrosschainHandler.CrosschainRelayData memory data =
            abi.decode(withdrawal.data, (IShinobiCashCrosschainHandler.CrosschainRelayData));

        uint256 destChainId = uint256(data.encodedDestination) >> 224;
        if (!s.withdrawalChainConfig[destChainId].isConfigured) revert DestinationChainNotConfigured();

        if (pd.relayFeeBPS > s.maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
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
        PoolOps.spend(s, uint256(pd.nullifierHash0));
        PoolOps.spend(s, uint256(pd.nullifierHash1));
        PoolOps.insert(s, uint256(pd.newCommitmentHash));

        // Create intent and emit
        IntentOps.IntentResult memory result = IntentOps.openIntent(
            s, destChainId, data,
            pd.withdrawnValue, pd.relayFeeBPS, pd.refundFeeBPS,
            pd.nullifierHash0, pd.refundCommitmentHash
        );

        emit CrosschainWithdraw2IntentRelayed(
            msg.sender, data.encodedDestination, s.asset,
            result.netAmount, result.relayFee, result.solverFee, result.orderId,
            Withdraw2Nullifiers(uint256(pd.nullifierHash0), uint256(pd.nullifierHash1))
        );
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.crosschainWithdraw2.selector);
    }
}
