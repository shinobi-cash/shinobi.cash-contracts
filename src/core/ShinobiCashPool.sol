// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {PrivacyPool} from "contracts/PrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "./interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "./interfaces/IWithdraw2Verifier.sol";
import {ICrossChainWithdraw2Verifier} from "./interfaces/ICrossChainWithdraw2Verifier.sol";
import {IShinobiCashPool} from "./interfaces/IShinobiCashPool.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {Withdraw2ProofLib} from "./libraries/Withdraw2ProofLib.sol";
import {CrossChainWithdraw2ProofLib} from "./libraries/CrossChainWithdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashPool
 * @author Karandeep Singh
 * @notice Abstract privacy pool with cross-chain and Withdraw2 capabilities
 * @dev Extends PrivacyPool with cross-chain withdrawal and 2:1 merge support
 */
abstract contract ShinobiCashPool is IShinobiCashPool, PrivacyPool {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using CrossChainWithdraw2ProofLib for CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ICrossChainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;
    IWithdraw2Verifier public immutable WITHDRAW2_VERIFIER;
    ICrossChainWithdraw2Verifier public immutable CROSSCHAIN_WITHDRAW2_VERIFIER;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validCrosschainWithdrawal(
        Withdrawal memory _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory _proof
    ) {
        if (msg.sender != _withdrawal.processooor) revert InvalidProcessooor();

        if (_proof.context() != uint256(keccak256(abi.encode(_withdrawal, SCOPE))) % Constants.SNARK_SCALAR_FIELD) {
            revert ContextMismatch();
        }

        if (_proof.stateTreeDepth() > MAX_TREE_DEPTH || _proof.ASPTreeDepth() > MAX_TREE_DEPTH) {
            revert InvalidTreeDepth();
        }

        if (!_isKnownRoot(_proof.stateRoot())) revert UnknownStateRoot();

        if (_proof.ASPRoot() != ENTRYPOINT.latestRoot()) revert IncorrectASPRoot();
        _;
    }

    modifier validWithdraw2(
        Withdrawal memory _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory _proof
    ) {
        if (msg.sender != _withdrawal.processooor) revert InvalidProcessooor();

        if (_proof.context() != uint256(keccak256(abi.encode(_withdrawal, SCOPE))) % Constants.SNARK_SCALAR_FIELD) {
            revert ContextMismatch();
        }

        if (_proof.stateTreeDepth() > MAX_TREE_DEPTH || _proof.ASPTreeDepth() > MAX_TREE_DEPTH) {
            revert InvalidTreeDepth();
        }

        if (!_isKnownRoot(_proof.stateRoot())) revert UnknownStateRoot();

        if (_proof.ASPRoot() != ENTRYPOINT.latestRoot()) revert IncorrectASPRoot();
        _;
    }

    modifier validCrossChainWithdraw2(
        Withdrawal memory _withdrawal,
        CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof memory _proof
    ) {
        if (msg.sender != _withdrawal.processooor) revert InvalidProcessooor();

        if (_proof.context() != uint256(keccak256(abi.encode(_withdrawal, SCOPE))) % Constants.SNARK_SCALAR_FIELD) {
            revert ContextMismatch();
        }

        if (_proof.stateTreeDepth() > MAX_TREE_DEPTH || _proof.ASPTreeDepth() > MAX_TREE_DEPTH) {
            revert InvalidTreeDepth();
        }

        if (!_isKnownRoot(_proof.stateRoot())) revert UnknownStateRoot();

        if (_proof.ASPRoot() != ENTRYPOINT.latestRoot()) revert IncorrectASPRoot();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        address _asset,
        ICrossChainWithdrawalProofVerifier _crossChainVerifier,
        IWithdraw2Verifier _withdraw2Verifier,
        ICrossChainWithdraw2Verifier _crossChainWithdraw2Verifier
    ) PrivacyPool(_entrypoint, _withdrawalVerifier, _ragequitVerifier, _asset) {
        if (address(_crossChainVerifier) == address(0)) revert InvalidCrossChainWithdrawalVerifier();
        if (address(_withdraw2Verifier) == address(0)) revert InvalidWithdraw2Verifier();
        if (address(_crossChainWithdraw2Verifier) == address(0)) revert InvalidCrossChainWithdraw2Verifier();

        CROSS_CHAIN_WITHDRAWAL_VERIFIER = _crossChainVerifier;
        WITHDRAW2_VERIFIER = _withdraw2Verifier;
        CROSSCHAIN_WITHDRAW2_VERIFIER = _crossChainWithdraw2Verifier;
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IShinobiCashPool
    function crosschainWithdraw(
        Withdrawal memory _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory _proof
    ) external override validCrosschainWithdrawal(_withdrawal, _proof) {
        if (!CROSS_CHAIN_WITHDRAWAL_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidCrosschainWithdrawalProof();
        }

        _spend(_proof.existingNullifierHash());
        _insert(_proof.newCommitmentHash());
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit CrosschainWithdrawn(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            _proof.existingNullifierHash(),
            _proof.newCommitmentHash(),
            _proof.refundCommitmentHash()
        );
    }

    /// @inheritdoc IShinobiCashPool
    function handleRefund(uint256 _refundCommitmentHash, uint256 _amount) external payable override onlyEntrypoint {
        if (msg.value != _amount) revert AmountMismatch();
        _insert(_refundCommitmentHash);
        emit RefundCommitmentInserted(msg.sender, _refundCommitmentHash, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW2 (2 inputs -> 1 output)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IShinobiCashPool
    function withdraw2(
        Withdrawal memory _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory _proof
    ) external override validWithdraw2(_withdrawal, _proof) {
        if (!WITHDRAW2_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidWithdraw2Proof();
        }

        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());
        _insert(_proof.newCommitmentHash());
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit Withdraw2Executed(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            Withdraw2Nullifiers(_proof.nullifierHash0(), _proof.nullifierHash1()),
            _proof.newCommitmentHash()
        );
    }

    /// @inheritdoc IShinobiCashPool
    function crossChainWithdraw2(
        Withdrawal memory _withdrawal,
        CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof memory _proof
    ) external override validCrossChainWithdraw2(_withdrawal, _proof) {
        if (!CROSSCHAIN_WITHDRAW2_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidCrossChainWithdraw2Proof();
        }

        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());
        _insert(_proof.newCommitmentHash());
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit CrossChainWithdraw2Executed(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            Withdraw2Nullifiers(_proof.nullifierHash0(), _proof.nullifierHash1()),
            _proof.newCommitmentHash(),
            _proof.refundCommitmentHash()
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function supportsCrossChain() external pure returns (bool) {
        return true;
    }
}
