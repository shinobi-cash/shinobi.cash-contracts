// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {PrivacyPool} from "contracts/PrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "./interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {IJoinSplitVerifier} from "./interfaces/IJoinSplitVerifier.sol";
import {IShinobiCashPool} from "./interfaces/IShinobiCashPool.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {JoinSplitProofLib} from "./libraries/JoinSplitProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashPool
 * @notice Abstract Cash Pool with cross-chain withdrawal capabilities
 * @dev Extends PrivacyPool with additional cross-chain withdrawal support
 *      Concrete implementations handle asset-specific transfer logic
 */
abstract contract ShinobiCashPool is IShinobiCashPool, PrivacyPool {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using JoinSplitProofLib for JoinSplitProofLib.JoinSplitProof;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The cross-chain withdrawal proof verifier contract
    ICrossChainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;

    /// @notice The JoinSplit proof verifier contract
    IJoinSplitVerifier public immutable JOINSPLIT_VERIFIER;

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

    modifier validJoinSplit(
        Withdrawal memory _withdrawal,
        JoinSplitProofLib.JoinSplitProof memory _proof
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

    /**
     * @notice Initialize the Shinobi Cash Pool with cross-chain and JoinSplit capabilities
     * @param _entrypoint The entrypoint contract address
     * @param _withdrawalVerifier The standard withdrawal proof verifier (8 signals)
     * @param _ragequitVerifier The ragequit proof verifier
     * @param _asset The asset address for this pool (native or ERC20)
     * @param _crossChainVerifier The cross-chain withdrawal proof verifier (9 signals)
     * @param _joinSplitVerifier The JoinSplit proof verifier (10 signals)
     */
    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        address _asset,
        ICrossChainWithdrawalProofVerifier _crossChainVerifier,
        IJoinSplitVerifier _joinSplitVerifier
    ) PrivacyPool(_entrypoint, _withdrawalVerifier, _ragequitVerifier, _asset) {
        if (address(_crossChainVerifier) == address(0)) revert InvalidCrosschainWithdrawalVerifier();
        if (address(_joinSplitVerifier) == address(0)) revert InvalidJoinSplitVerifier();
        CROSS_CHAIN_WITHDRAWAL_VERIFIER = _crossChainVerifier;
        JOINSPLIT_VERIFIER = _joinSplitVerifier;
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a cross-chain withdrawal with enhanced 9-signal proof
     * @dev Follows the same pattern as standard withdraw() but with cross-chain verifier and additional refund logic
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The enhanced 9-signal cross-chain proof
     */
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

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the entrypoint with ETH for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund
     * @param _amount The amount being refunded (for validation)
     */
    function handleRefund(uint256 _refundCommitmentHash, uint256 _amount) external payable override onlyEntrypoint {
        if (msg.value != _amount) revert AmountMismatch();

        // Insert the refund commitment into the merkle tree
        _insert(_refundCommitmentHash);

        emit RefundCommitmentInserted(msg.sender,_refundCommitmentHash, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        JOINSPLIT WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a JoinSplit withdrawal combining 2 inputs into 1 output (change) with withdrawal
     * @dev Spends 2 nullifiers and inserts 1 change commitment in a single transaction
     * @param _withdrawal The withdrawal data
     * @param _proof The JoinSplit 10-signal proof
     */
    function joinSplitWithdraw(
        Withdrawal memory _withdrawal,
        JoinSplitProofLib.JoinSplitProof memory _proof
    ) external override validJoinSplit(_withdrawal, _proof) {
        if (!JOINSPLIT_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidJoinSplitProof();
        }

        // Spend both input nullifiers
        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());

        // Insert change commitment
        _insert(_proof.newCommitmentHash());

        // Transfer withdrawn value
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit JoinSplitWithdrawn(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            _proof.nullifierHash0(),
            _proof.nullifierHash1(),
            _proof.newCommitmentHash()
        );
    }

    /**
     * @notice Process a cross-chain JoinSplit withdrawal
     * @dev Combines 2 inputs, creates 1 change output, and includes refund commitment for cross-chain recovery
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The JoinSplit 10-signal proof with refund commitment
     */
    function crosschainJoinSplitWithdraw(
        Withdrawal memory _withdrawal,
        JoinSplitProofLib.JoinSplitProof memory _proof
    ) external override validJoinSplit(_withdrawal, _proof) {
        if (!JOINSPLIT_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidJoinSplitProof();
        }

        // Spend both input nullifiers
        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());

        // Insert change commitment
        _insert(_proof.newCommitmentHash());

        // Transfer withdrawn value to processooor (entrypoint for cross-chain)
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit CrosschainJoinSplitWithdrawn(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            _proof.nullifierHash0(),
            _proof.nullifierHash1(),
            _proof.newCommitmentHash(),
            _proof.refundCommitmentHash()
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Check if this pool supports cross-chain withdrawals
     * @return True, as this pool supports cross-chain functionality
     */
    function supportsCrossChain() external pure returns (bool) {
        return true;
    }

}