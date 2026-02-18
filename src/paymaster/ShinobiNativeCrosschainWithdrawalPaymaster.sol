// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {IShinobiCashEntrypoint} from "../core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashCrosschainHandler} from "../core/interfaces/IShinobiCashCrosschainHandler.sol";
import {ShinobiCashPool} from "../core/ShinobiCashPool.sol";
import {ICrosschainWithdrawalProofVerifier} from "../core/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {CrosschainProofLib} from "../core/libraries/CrosschainProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";

/**
 * @title ShinobiNativeCrosschainWithdrawalPaymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for cross-chain privacy pool withdrawals and refunds
 * @dev Validates 13-signal ZK proofs for withdrawals and intent validation for refunds
 * @dev Single paymaster handles both operations, receiving relay fee (withdrawal) and refund fee (refund)
 */
contract ShinobiNativeCrosschainWithdrawalPaymaster is BasePaymaster {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;
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

    uint256 internal constant _VALIDATION_FAILED = 1;
    uint256 public constant MIN_POST_OP_GAS_LIMIT = 50_000;

    // Withdrawal gas limits (ZK proof verification + pool operations)
    uint256 public constant MIN_CALL_GAS_LIMIT_WITHDRAWAL = 687_500;
    uint256 public constant MIN_VERIFICATION_GAS_WITHDRAWAL = 500_000;

    // Refund gas limits (no ZK verification, simpler flow)
    uint256 public constant MIN_CALL_GAS_LIMIT_REFUND = 350_000;
    uint256 public constant MIN_VERIFICATION_GAS_REFUND = 200_000;

    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;
    ShinobiCashPool public immutable ETH_POOL;
    IShinobiInputSettler public immutable INPUT_SETTLER;
    address public expectedSmartAccount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CrosschainWithdrawalSponsored(
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

    event ExpectedSmartAccountUpdated(
        address indexed previousAccount,
        address indexed newAccount
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCallData();
    error InsufficientPostOpGasLimit();
    error InsufficientCallGasLimit();
    error InsufficientPaymasterVerificationGas();
    error CrosschainWithdrawalValidationFailed();
    error InsufficientPaymasterCost();
    error WrongFeeRecipient();
    error UnauthorizedCaller();
    error InvalidProcessooor();
    error InvalidScope();
    error ZeroFeeNotAllowed();
    error ExpectedSmartAccountNotSet();
    error UnauthorizedSmartAccount();
    error SmartAccountNotDeployed();
    error InvalidAddress();
    error UnsupportedOperation();
    error InvalidOrderStatus();
    error InvalidRefundTarget();
    error InvalidSelector();
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
        ShinobiCashPool _ethShinobiCashPool,
        IShinobiInputSettler _inputSettler
    ) BasePaymaster(_entryPoint) {
        if (address(_shinobiCashEntrypoint) == address(0)) revert InvalidAddress();
        if (address(_ethShinobiCashPool) == address(0)) revert InvalidAddress();
        if (address(_inputSettler) == address(0)) revert InvalidAddress();
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_POOL = _ethShinobiCashPool;
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
                        EMBEDDED WITHDRAWAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal relay method that mirrors ShinobiCashEntrypoint.crosschainWithdrawal()
     * @dev Called internally to validate withdrawal proofs and store results in transient storage
     */
    function crosschainWithdrawal(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof calldata _proof,
        uint256 _scope
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (_withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (_withdrawal.data.length != 96) revert InvalidRelayDataLength();

        IShinobiCashCrosschainHandler.CrosschainRelayData memory relayData = abi.decode(
            _withdrawal.data,
            (IShinobiCashCrosschainHandler.CrosschainRelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (_scope != ETH_POOL.SCOPE()) revert InvalidScope();

        uint32 chainId = uint32(uint256(relayData.encodedDestination) >> 224);
        (bool isConfigured,,,,,) = SHINOBI_CASH_ENTRYPOINT.withdrawalChainConfig(chainId);
        if (!isConfigured) revert DestinationChainNotConfigured();

        uint256 relayFeeBPS = _proof.relayFeeBPS();
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        
        uint256 maxSolver = SHINOBI_CASH_ENTRYPOINT.maxSolverFeeBPS();
        if (maxSolver == 0) revert MaxSolverFeeBPSNotSet();
        if (relayData.solverFeeBPS > maxSolver) revert SolverFeeGreaterThanMax();

        if (!_validateCrosschainWithdrawCall(_withdrawal, _proof)) revert CrosschainWithdrawalValidationFailed();

        uint256 withdrawnValue = _proof.withdrawnValue();
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
        if (scope != ETH_POOL.SCOPE()) revert InvalidScope();
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

            emit CrosschainWithdrawalSponsored(
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

        if (!_validateCrosschainWithdrawal(value, data)) {
            revert CrosschainWithdrawalValidationFailed();
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
        // Bundler will only include this UserOp after intent expires
        uint48 validAfter = uint48(intentExpires);
        uint48 validUntil = 0; // No upper bound
        bool sigFailed = false;
        validationData = _packValidationData(sigFailed, validUntil, validAfter);
    }

    /*//////////////////////////////////////////////////////////////
                        EMBEDDED WITHDRAWAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateCrosschainWithdrawal(
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        // Target already validated in router
        if (value != 0) return false;

        (bool success, ) = address(this).call(data);
        return success;
    }

    /*//////////////////////////////////////////////////////////////
                         CROSS-CHAIN PROOF VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateCrosschainWithdrawCall(
        IPrivacyPool.Withdrawal memory withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof memory proof
    ) internal view returns (bool) {
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_POOL.SCOPE()))
        ) % (Constants.SNARK_SCALAR_FIELD);

        if (proof.context() != expectedContext) return false;

        if (
            proof.stateTreeDepth() > ETH_POOL.MAX_TREE_DEPTH() ||
            proof.ASPTreeDepth() > ETH_POOL.MAX_TREE_DEPTH()
        ) return false;

        if (!_isKnownRoot(proof.stateRoot())) return false;
        if (proof.ASPRoot() != SHINOBI_CASH_ENTRYPOINT.latestRoot()) return false;
        if (ETH_POOL.nullifierHashes(proof.existingNullifierHash())) return false;
        if (proof.refundCommitmentHash() == 0) return false;

        if (!ICrosschainWithdrawalProofVerifier(ETH_POOL.CROSS_CHAIN_WITHDRAWAL_VERIFIER()).verifyProof(
            proof.pA,
            proof.pB,
            proof.pC,
            proof.pubSignals
        )) return false;

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _isKnownRoot(uint256 _root) internal view returns (bool) {
        if (_root == 0) return false;

        uint32 _index = ETH_POOL.currentRootIndex();
        uint32 ROOT_HISTORY_SIZE = ETH_POOL.ROOT_HISTORY_SIZE();

        for (uint32 _i = 0; _i < ROOT_HISTORY_SIZE; _i++) {
            if (_root == ETH_POOL.roots(_index)) return true;
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