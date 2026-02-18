// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {IShinobiCashEntrypoint} from "../core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashCrosschainHandler} from "../core/interfaces/IShinobiCashCrosschainHandler.sol";
import {IShinobiCashPool} from "../core/interfaces/IShinobiCashPool.sol";
import {ICrosschainWithdraw2Verifier} from "../core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {CrosschainWithdraw2ProofLib} from "../core/libraries/CrosschainWithdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";

/**
 * @title ShinobiNativeCrosschainWithdraw2Paymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for cross-chain Withdraw2 (2:1 merge) operations and refunds
 * @dev Validates 14-signal ZK proofs with 2 nullifiers and refund commitment
 * @dev Single paymaster handles both withdrawal and refund operations
 */
contract ShinobiNativeCrosschainWithdraw2Paymaster is BasePaymaster {
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;
    using UserOperationLib for PackedUserOperation;
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    enum OperationType {
        Withdrawal,
        Refund
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MIN_POST_OP_GAS_LIMIT = 50_000;

    // Withdrawal gas limits (ZK proof verification + pool operations)
    uint256 public constant MIN_CALL_GAS_LIMIT_WITHDRAWAL = 750_000;
    uint256 public constant MIN_VERIFICATION_GAS_WITHDRAWAL = 550_000;

    // Refund gas limits (no ZK verification, simpler flow)
    uint256 public constant MIN_CALL_GAS_LIMIT_REFUND = 350_000;
    uint256 public constant MIN_VERIFICATION_GAS_REFUND = 200_000;

    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;
    IShinobiCashPool public immutable ETH_CASH_POOL;
    ICrosschainWithdraw2Verifier public immutable CROSSCHAIN_WITHDRAW2_VERIFIER;
    IShinobiInputSettler public immutable INPUT_SETTLER;
    address public expectedSmartAccount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CrosschainWithdraw2Sponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        bool success
    );

    event RefundSponsored(
        bytes32 indexed orderId,
        bytes32 indexed userOpHash,
        uint256 actualCost,
        bool success
    );

    event ExpectedSmartAccountUpdated(address indexed previousAccount, address indexed newAccount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCallData();
    error InsufficientPostOpGasLimit();
    error InsufficientCallGasLimit();
    error InsufficientPaymasterVerificationGas();
    error CrosschainWithdraw2ValidationFailed();
    error InsufficientPaymasterCost();
    error WrongFeeRecipient();
    error UnauthorizedCaller();
    error InvalidProcessooor();
    error InvalidScope();
    error ZeroFeeNotAllowed();
    error ExpectedSmartAccountNotSet();
    error UnauthorizedSmartAccount();
    error SmartAccountNotDeployed();
    error NullifierAlreadySpent();
    error InvalidCrosschainWithdraw2Proof();
    error InvalidAddress();
    error UnsupportedOperation();
    error InvalidOrderStatus();
    error InvalidRefundTarget();
    error RefundValidationFailed();
    error MaxSolverFeeBPSNotSet();
    error DestinationChainNotConfigured();
    error RelayFeeGreaterThanMax();
    error SolverFeeGreaterThanMax();
    error InvalidRelayDataLength();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        ICrosschainWithdraw2Verifier _crossChainWithdraw2Verifier,
        IShinobiInputSettler _inputSettler
    ) BasePaymaster(_entryPoint) {
        if (address(_shinobiCashEntrypoint) == address(0)) revert InvalidAddress();
        if (address(_ethCashPool) == address(0)) revert InvalidAddress();
        if (address(_crossChainWithdraw2Verifier) == address(0)) revert InvalidAddress();
        if (address(_inputSettler) == address(0)) revert InvalidAddress();
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_CASH_POOL = _ethCashPool;
        CROSSCHAIN_WITHDRAW2_VERIFIER = _crossChainWithdraw2Verifier;
        INPUT_SETTLER = _inputSettler;
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        SMART ACCOUNT CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function setExpectedSmartAccount(address account) external onlyOwner {
        if (account == address(0)) revert InvalidProcessooor();
        address previousAccount = expectedSmartAccount;
        expectedSmartAccount = account;
        emit ExpectedSmartAccountUpdated(previousAccount, account);
    }

    /*//////////////////////////////////////////////////////////////
                    EMBEDDED CROSSCHAIN WITHDRAW2 VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal validation method for CrosschainWithdraw2 proofs
     * @dev Called internally to validate proofs and store results in transient storage
     */
    function crossChainWithdrawal2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof,
        uint256 scope
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        IShinobiCashCrosschainHandler.CrosschainRelayData memory relayData = abi.decode(
            withdrawal.data,
            (IShinobiCashCrosschainHandler.CrosschainRelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early configuration checks - fail fast before expensive ZK verification
        uint256 maxSolver = SHINOBI_CASH_ENTRYPOINT.maxSolverFeeBPS();
        if (maxSolver == 0) revert MaxSolverFeeBPSNotSet();

        uint32 chainId = uint32(uint256(relayData.encodedDestination) >> 224);
        (bool isConfigured,,,,,) = SHINOBI_CASH_ENTRYPOINT.withdrawalChainConfig(chainId);
        if (!isConfigured) revert DestinationChainNotConfigured();

        uint256 relayFeeBPS = proof.relayFeeBPS();
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (relayData.solverFeeBPS > maxSolver) revert SolverFeeGreaterThanMax();

        if (!_validateCrosschainWithdraw2Proof(withdrawal, proof)) revert CrosschainWithdraw2ValidationFailed();

        uint256 withdrawnValue = proof.withdrawnValue();
        // relayFeeBPS already read above for validation
        address withdrawalRecipient = address(uint160(uint256(relayData.encodedDestination)));

        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, withdrawalRecipient)
        }

        if (relayFeeBPS == 0) revert ZeroFeeNotAllowed();
    }

    /**
     * @notice Internal validator method that mirrors IShinobiInputSettler.refund()
     * @dev Called internally to validate refund intent and store results in transient storage
     */
    function refund(ShinobiIntent calldata intent) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();

        // Validate order status (must be Deposited, not filled or refunded)
        bytes32 orderId = intent.orderIdentifier();
        if (INPUT_SETTLER.orderStatus(orderId) != IShinobiInputSettler.OrderStatus.Deposited) {
            revert InvalidOrderStatus();
        }

        // Decode refundCalldata: (target, handleRefundCalldata)
        (address refundTarget, bytes memory handleRefundCalldata) = abi.decode(
            intent.refundCalldata,
            (address, bytes)
        );

        // Validate refund target is entrypoint
        if (refundTarget != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidRefundTarget();

        // Decode handleRefund params directly (simple types, no complex structs)
        // Layout: selector(4) + refundCommitmentHash(32) + feeRecipient(32) + refundFeeBPS(32) + scope(32)
        address feeRecipient;
        uint256 refundFeeBPS;
        uint256 scope;
        assembly {
            let dataPtr := add(handleRefundCalldata, 32) // skip bytes length prefix
            // skip selector (4) + refundCommitmentHash (32) = 36 bytes
            feeRecipient := mload(add(dataPtr, 36))
            refundFeeBPS := mload(add(dataPtr, 68))
            scope := mload(add(dataPtr, 100))
        }

        // Validate params
        if (feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();
        if (refundFeeBPS == 0) revert ZeroFeeNotAllowed();

        // Calculate expected fee
        uint256 escrowAmount = intent.inputs[0][1];
        uint256 expectedFeeAmount = (escrowAmount * refundFeeBPS) / 10_000;

        // Store in transient storage for _handleRefundValidation
        uint32 intentExpires = intent.expires;
        assembly {
            tstore(3, orderId)
            tstore(4, expectedFeeAmount)
            tstore(5, intentExpires)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            POST-OP OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function _postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        // Decode operation type from context
        OperationType opType = abi.decode(context, (OperationType));

        uint256 postOpCost = MIN_POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualCost = actualGasCost + postOpCost;

        if (opType == OperationType.Withdrawal) {
            (
                ,
                bytes32 userOpHash,
                address withdrawalRecipient,
                uint256 expectedFeeAmount
            ) = abi.decode(context, (OperationType, bytes32, address, uint256));

            if (expectedFeeAmount > 0) {
                entryPoint.depositTo{value: expectedFeeAmount}(address(this));
            }

            emit CrosschainWithdraw2Sponsored(
                withdrawalRecipient,
                userOpHash,
                actualCost,
                mode == IPaymaster.PostOpMode.opSucceeded
            );
        } else if (opType == OperationType.Refund) {
            (
                ,
                bytes32 userOpHash,
                bytes32 orderId,
                uint256 expectedFeeAmount
            ) = abi.decode(context, (OperationType, bytes32, bytes32, uint256));

            if (expectedFeeAmount > 0) {
                entryPoint.depositTo{value: expectedFeeAmount}(address(this));
            }

            emit RefundSponsored(
                orderId,
                userOpHash,
                actualCost,
                mode == IPaymaster.PostOpMode.opSucceeded
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                          PAYMASTER VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        // Common checks
        if (expectedSmartAccount == address(0)) revert ExpectedSmartAccountNotSet();
        if (userOp.sender != expectedSmartAccount) revert UnauthorizedSmartAccount();
        if (userOp.initCode.length > 0) revert SmartAccountNotDeployed();
        if (userOp.unpackPostOpGasLimit() < MIN_POST_OP_GAS_LIMIT) revert InsufficientPostOpGasLimit();

        // Extract target from smart account execute call
        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);

        // Route based on target address
        if (target == address(SHINOBI_CASH_ENTRYPOINT)) {
            return _handleWithdrawalValidation(userOp, userOpHash, maxCost, value, data);
        } else if (target == address(INPUT_SETTLER)) {
            return _handleRefundValidation(userOp, userOpHash, maxCost, value, data);
        } else {
            revert UnsupportedOperation();
        }
    }

    function _handleWithdrawalValidation(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory context, uint256 validationData) {
        // Withdrawal-specific gas limits
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT_WITHDRAWAL) revert InsufficientCallGasLimit();
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_VERIFICATION_GAS_WITHDRAWAL) {
            revert InsufficientPaymasterVerificationGas();
        }

        if (!_validateCrosschainWithdraw2Withdrawal(value, data)) {
            revert CrosschainWithdraw2ValidationFailed();
        }

        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        address withdrawalRecipient;
        assembly {
            withdrawnValue := tload(0)
            relayFeeBPS := tload(1)
            withdrawalRecipient := tload(2)
        }

        uint256 expectedFeeAmount = (withdrawnValue * relayFeeBPS) / 10_000;
        if (expectedFeeAmount < maxCost) revert InsufficientPaymasterCost();

        assembly {
            tstore(0, 0)
            tstore(1, 0)
            tstore(2, 0)
        }

        context = abi.encode(OperationType.Withdrawal, userOpHash, withdrawalRecipient, expectedFeeAmount);
        validationData = 0; // No time restrictions for withdrawal
    }

    function _handleRefundValidation(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory context, uint256 validationData) {
        // Refund-specific gas limits
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT_REFUND) revert InsufficientCallGasLimit();
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_VERIFICATION_GAS_REFUND) {
            revert InsufficientPaymasterVerificationGas();
        }

        // Value must be 0 for refund calls
        if (value != 0) revert RefundValidationFailed();

        // Call self to validate - Solidity dispatcher handles decoding
        (bool success,) = address(this).call(data);
        if (!success) revert RefundValidationFailed();

        // Read values from transient storage (set by refund() validator)
        bytes32 orderId;
        uint256 expectedFeeAmount;
        uint32 intentExpires;
        assembly {
            orderId := tload(3)
            expectedFeeAmount := tload(4)
            intentExpires := tload(5)
            // Clear transient storage
            tstore(3, 0)
            tstore(4, 0)
            tstore(5, 0)
        }

        if (expectedFeeAmount < maxCost) revert InsufficientPaymasterCost();

        // Encode context for postOp
        context = abi.encode(OperationType.Refund, userOpHash, orderId, expectedFeeAmount);

        // Return validAfter = intent.expires (ERC-4337 time-lock)
        uint48 validAfter = uint48(intentExpires);
        uint48 validUntil = 0;
        bool sigFailed = false;
        validationData = _packValidationData(sigFailed, validUntil, validAfter);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAW2 VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateCrosschainWithdraw2Withdrawal(
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        // Target already validated in router
        if (value != 0) return false;

        (bool success,) = address(this).call(data);
        return success;
    }

    function _validateCrosschainWithdraw2Proof(
        IPrivacyPool.Withdrawal memory withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof
    ) internal view returns (bool) {
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_CASH_POOL.SCOPE()))
        ) % Constants.SNARK_SCALAR_FIELD;

        if (proof.context() != expectedContext) return false;

        if (
            proof.stateTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH() ||
            proof.ASPTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH()
        ) return false;

        if (!_isKnownRoot(proof.stateRoot())) return false;
        if (proof.ASPRoot() != SHINOBI_CASH_ENTRYPOINT.latestRoot()) return false;
        if (ETH_CASH_POOL.nullifierHashes(proof.nullifierHash0())) return false;
        if (ETH_CASH_POOL.nullifierHashes(proof.nullifierHash1())) return false;
        if (proof.refundCommitmentHash() == 0) return false;

        if (!CROSSCHAIN_WITHDRAW2_VERIFIER.verifyProof(
            proof.pA,
            proof.pB,
            proof.pC,
            proof.pubSignals
        )) return false;

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _isKnownRoot(uint256 _root) internal view returns (bool) {
        if (_root == 0) return false;

        uint32 _index = ETH_CASH_POOL.currentRootIndex();
        uint32 ROOT_HISTORY_SIZE = ETH_CASH_POOL.ROOT_HISTORY_SIZE();

        for (uint32 _i = 0; _i < ROOT_HISTORY_SIZE; _i++) {
            if (_root == ETH_CASH_POOL.roots(_index)) return true;
            _index = (_index + ROOT_HISTORY_SIZE - 1) % ROOT_HISTORY_SIZE;
        }

        return false;
    }

    function _extractExecuteCall(bytes calldata callData)
        internal
        pure
        returns (address target, uint256 value, bytes memory data)
    {
        if (callData.length < 4) revert InvalidCallData();

        bytes4 selector = bytes4(callData[:4]);
        if (selector != 0xb61d27f6) revert InvalidCallData();

        (target, value, data) = abi.decode(callData[4:], (address, uint256, bytes));
    }
}
