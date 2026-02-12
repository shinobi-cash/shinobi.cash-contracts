// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {PrivacyPool} from "contracts/PrivacyPool.sol";
import {ICrosschainWithdrawalProofVerifier} from "./interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "./interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "./interfaces/ICrosschainWithdraw2Verifier.sol";
import {IShinobiCashPool} from "./interfaces/IShinobiCashPool.sol";
import {CrosschainProofLib} from "./libraries/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "./libraries/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "./libraries/CrosschainWithdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashPool
 * @author Karandeep Singh
 * @notice Abstract privacy pool with cross-chain and Withdraw2 capabilities
 * @dev Extends PrivacyPool with cross-chain withdrawal and 2:1 merge support
 */
abstract contract ShinobiCashPool is IShinobiCashPool, PrivacyPool {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ICrosschainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;
    IWithdraw2Verifier public immutable WITHDRAW2_VERIFIER;
    ICrosschainWithdraw2Verifier public immutable CROSSCHAIN_WITHDRAW2_VERIFIER;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validCrosschainWithdrawal(
        Withdrawal memory _withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof memory _proof
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

    modifier validCrosschainWithdraw2(
        Withdrawal memory _withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory _proof
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
        ICrosschainWithdrawalProofVerifier _crossChainVerifier,
        IWithdraw2Verifier _withdraw2Verifier,
        ICrosschainWithdraw2Verifier _crossChainWithdraw2Verifier
    ) PrivacyPool(_entrypoint, _withdrawalVerifier, _ragequitVerifier, _asset) {
        if (address(_crossChainVerifier) == address(0)) revert InvalidCrosschainWithdrawalVerifier();
        if (address(_withdraw2Verifier) == address(0)) revert InvalidWithdraw2Verifier();
        if (address(_crossChainWithdraw2Verifier) == address(0)) revert InvalidCrosschainWithdraw2Verifier();

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
        CrosschainProofLib.CrosschainWithdrawProof memory _proof
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
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory _proof
    ) external override validCrosschainWithdraw2(_withdrawal, _proof) {
        if (!CROSSCHAIN_WITHDRAW2_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidCrosschainWithdraw2Proof();
        }

        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());
        _insert(_proof.newCommitmentHash());
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit CrosschainWithdraw2Executed(
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

    function supportsCrosschain() external pure returns (bool) {
        return true;
    }
}
