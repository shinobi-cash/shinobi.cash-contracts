// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {PrivacyPool} from "contracts/PrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "./interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "./interfaces/IWithdraw2Verifier.sol";
import {IShinobiCashPool} from "./interfaces/IShinobiCashPool.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {Withdraw2ProofLib} from "./libraries/Withdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashPool
 * @notice Abstract Cash Pool with cross-chain withdrawal capabilities
 * @dev Extends PrivacyPool with additional cross-chain withdrawal support
 *      Concrete implementations handle asset-specific transfer logic
 */
abstract contract ShinobiCashPool is IShinobiCashPool, PrivacyPool {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The cross-chain withdrawal proof verifier contract
    ICrossChainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;

    /// @notice The Withdraw2 proof verifier contract
    IWithdraw2Verifier public immutable WITHDRAW2_VERIFIER;

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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the Shinobi Cash Pool with cross-chain and Withdraw2 capabilities
     * @param _entrypoint The entrypoint contract address
     * @param _withdrawalVerifier The standard withdrawal proof verifier (8 signals)
     * @param _ragequitVerifier The ragequit proof verifier
     * @param _asset The asset address for this pool (native or ERC20)
     * @param _crossChainVerifier The cross-chain withdrawal proof verifier (9 signals)
     * @param _withdraw2Verifier The Withdraw2 proof verifier (10 signals)
     */
    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        address _asset,
        ICrossChainWithdrawalProofVerifier _crossChainVerifier,
        IWithdraw2Verifier _withdraw2Verifier
    ) PrivacyPool(_entrypoint, _withdrawalVerifier, _ragequitVerifier, _asset) {
        if (address(_crossChainVerifier) == address(0)) revert InvalidCrosschainWithdrawalVerifier();
        if (address(_withdraw2Verifier) == address(0)) revert InvalidWithdraw2Verifier();
        CROSS_CHAIN_WITHDRAWAL_VERIFIER = _crossChainVerifier;
        WITHDRAW2_VERIFIER = _withdraw2Verifier;
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
                        WITHDRAW2 (2 inputs -> 1 output)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Process a Withdraw2 combining 2 inputs into 1 output (change) with withdrawal
     * @dev Spends 2 nullifiers and inserts 1 change commitment in a single transaction
     * @param _withdrawal The withdrawal data
     * @param _proof The Withdraw2 10-signal proof
     */
    function withdraw2(
        Withdrawal memory _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory _proof
    ) external override validWithdraw2(_withdrawal, _proof) {
        if (!WITHDRAW2_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidWithdraw2Proof();
        }

        // Spend both input nullifiers
        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());

        // Insert change commitment
        _insert(_proof.newCommitmentHash());

        // Transfer withdrawn value
        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit Withdraw2Executed(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            Withdraw2Nullifiers(_proof.nullifierHash0(), _proof.nullifierHash1()),
            _proof.newCommitmentHash()
        );
    }

    /**
     * @notice Process a cross-chain Withdraw2
     * @dev Combines 2 inputs, creates 1 change output, and includes refund commitment for cross-chain recovery
     * @param _withdrawal The cross-chain withdrawal data
     * @param _proof The Withdraw2 10-signal proof with refund commitment
     */
    function crosschainWithdraw2(
        Withdrawal memory _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory _proof
    ) external override validWithdraw2(_withdrawal, _proof) {
        if (!WITHDRAW2_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidWithdraw2Proof();
        }

        // Spend both input nullifiers
        _spend(_proof.nullifierHash0());
        _spend(_proof.nullifierHash1());

        // Insert change commitment
        _insert(_proof.newCommitmentHash());

        // Transfer withdrawn value to processooor (entrypoint for cross-chain)
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
    /**
     * @notice Check if this pool supports cross-chain withdrawals
     * @return True, as this pool supports cross-chain functionality
     */
    function supportsCrossChain() external pure returns (bool) {
        return true;
    }

}
