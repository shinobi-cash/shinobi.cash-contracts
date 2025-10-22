// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {PrivacyPool} from "contracts/PrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "./interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashPool
 * @notice Abstract Cash Pool with cross-chain withdrawal capabilities
 * @dev Extends PrivacyPool with additional cross-chain withdrawal support
 *      Concrete implementations handle asset-specific transfer logic
 */
abstract contract ShinobiCashPool is PrivacyPool {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The cross-chain withdrawal proof verifier contract
    ICrossChainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a cross-chain withdrawal is executed from the pool
     * @param processooor The processor contract handling the cross-chain logic
     * @param withdrawnValue The amount withdrawn
     * @param existingNullifierHash The nullifier hash that was spent
     * @param newCommitmentHash The new commitment hash that was inserted
     * @param refundCommitmentHash The commitment hash for potential refunds if cross-chain intent fails (cross-chain specific)
     */
    event CrossChainWithdrawn(
        address indexed processooor,
        uint256 withdrawnValue,
        uint256 indexed existingNullifierHash,
        uint256 indexed newCommitmentHash,
        uint256 refundCommitmentHash
    );

    /**
     * @notice Emitted when a refund commitment is inserted for failed cross-chain withdrawal
     * @param processoor The entrypoint that processed the refund
     * @param refundCommitmentHash The commitment hash inserted for refund
     * @param refundAmount The amount available for refund
     */
    event RefundCommitmentInserted(
        address indexed processoor,
        uint256 indexed refundCommitmentHash,
        uint256 refundAmount
    );

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when cross-chain verifier address is zero
    error InvalidCrossChainWithdrawalVerifier();

    /// @notice Thrown when cross-chain proof verification fails
    error InvalidCrossChainWithdrawalProof();

    /// @notice Thrown when cross-chain proof structure is invalid
    error InvalidCrossChainWithdrawalProofStructure();

    /// @notice Thrown when cross-chain withdrawal is called by unauthorized processor
    error UnauthorizedCrossChainProcessor();

    /// @notice Thrown when the state root is invalid
    error InvalidStateRoot();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validCrossChainWithdrawal(
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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the Shinobi Cash Pool with cross-chain capabilities
     * @param _entrypoint The entrypoint contract address
     * @param _withdrawalVerifier The standard withdrawal proof verifier (8 signals)
     * @param _ragequitVerifier The ragequit proof verifier
     * @param _asset The asset address for this pool (native or ERC20)
     * @param _crossChainVerifier The cross-chain withdrawal proof verifier (9 signals)
     */
    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        address _asset,
        ICrossChainWithdrawalProofVerifier _crossChainVerifier
    ) PrivacyPool(_entrypoint, _withdrawalVerifier, _ragequitVerifier, _asset) {
        if (address(_crossChainVerifier) == address(0)) revert InvalidCrossChainWithdrawalVerifier();
        CROSS_CHAIN_WITHDRAWAL_VERIFIER = _crossChainVerifier;
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
    function crossChainWithdraw(
        Withdrawal memory _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory _proof
    ) external validCrossChainWithdrawal(_withdrawal, _proof) {
        if (!CROSS_CHAIN_WITHDRAWAL_VERIFIER.verifyProof(_proof.pA, _proof.pB, _proof.pC, _proof.pubSignals)) {
            revert InvalidCrossChainWithdrawalProof();
        }

        _spend(_proof.existingNullifierHash());

        _insert(_proof.newCommitmentHash());

        _push(_withdrawal.processooor, _proof.withdrawnValue());

        emit CrossChainWithdrawn(
            _withdrawal.processooor,
            _proof.withdrawnValue(),
            _proof.existingNullifierHash(),
            _proof.newCommitmentHash(),
            _proof.refundCommitmentHash()
        );
         emit Withdrawn(
            _withdrawal.processooor, _proof.withdrawnValue(), _proof.existingNullifierHash(), _proof.newCommitmentHash()
        );
    }

    /**
     * @notice Insert refund commitment into the merkle tree
     * @dev Can only be called by the entrypoint for processing refunds
     * @param _refundCommitmentHash The commitment hash to insert for refund
     * @return The updated root after insertion
     */
    function insertRefundCommitment(uint256 _refundCommitmentHash) external onlyEntrypoint returns (uint256) {
        return _insert(_refundCommitmentHash);
    }

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the entrypoint with ETH for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund
     * @param _amount The amount being refunded (for validation)
     */
    function handleRefund(uint256 _refundCommitmentHash, uint256 _amount) external payable onlyEntrypoint {
        require(msg.value == _amount, "ETH amount mismatch");
        
        // Insert the refund commitment into the merkle tree
        _insert(_refundCommitmentHash);
        
        emit RefundCommitmentInserted(msg.sender,_refundCommitmentHash, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the cross-chain verifier address
     * @return The address of the cross-chain withdrawal proof verifier
     */
    function crossChainVerifier() external view returns (address) {
        return address(CROSS_CHAIN_WITHDRAWAL_VERIFIER);
    }

    /**
     * @notice Check if this pool supports cross-chain withdrawals
     * @return True, as this pool supports cross-chain functionality
     */
    function supportsCrossChain() external pure returns (bool) {
        return true;
    }

}