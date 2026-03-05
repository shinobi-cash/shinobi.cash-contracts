// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {IPoolDiamond} from "../pool/interfaces/IPoolDiamond.sol";
import {CrosschainWithdrawData} from "../pool/libraries/Types.sol";
import {ICrosschainWithdrawalProofVerifier} from "../verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {CrosschainProofLib} from "../proofLibs/CrosschainProofLib.sol";
import {Constants} from "../pool/libraries/Constants.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";

/**
 * @title CrosschainWithdrawalPaymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for cross-chain privacy pool withdrawals and refunds via PoolDiamond
 * @dev Validates cross-chain ZK proofs for withdrawals and intent validation for refunds
 */
contract CrosschainWithdrawalPaymaster is BasePaymaster {
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

    uint256 public constant MIN_POST_OP_GAS_LIMIT = 50_000;

    uint256 public constant MIN_CALL_GAS_LIMIT_WITHDRAWAL = 687_500;
    uint256 public constant MIN_VERIFICATION_GAS_WITHDRAWAL = 500_000;

    uint256 public constant MIN_CALL_GAS_LIMIT_REFUND = 350_000;
    uint256 public constant MIN_VERIFICATION_GAS_REFUND = 200_000;

    IPoolDiamond public immutable POOL_DIAMOND;
    ICrosschainWithdrawalProofVerifier public immutable CROSSCHAIN_VERIFIER;
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
    error RefundValidationFailed();
    error MaxSolverFeeBPSNotSet();
    error MaxRefundFeeBPSNotSet();
    error WithdrawalInputSettlerNotSet();
    error DestinationChainNotConfigured();
    error RelayFeeGreaterThanMax();
    error SolverFeeGreaterThanMax();
    error RefundFeeGreaterThanMax();
    error RefundFeeBPSZero();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IPoolDiamond _poolDiamond,
        ICrosschainWithdrawalProofVerifier _crosschainVerifier,
        IShinobiInputSettler _inputSettler
    ) BasePaymaster(_entryPoint) {
        if (address(_poolDiamond) == address(0)) revert InvalidAddress();
        if (address(_crosschainVerifier) == address(0)) revert InvalidAddress();
        if (address(_inputSettler) == address(0)) revert InvalidAddress();
        POOL_DIAMOND = _poolDiamond;
        CROSSCHAIN_VERIFIER = _crosschainVerifier;
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
                    EMBEDDED CROSSCHAIN WITHDRAWAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal validation matching diamond's crosschainWithdraw() signature
     * @dev Called via self-call to leverage Solidity's built-in dispatcher
     */
    function crosschainWithdraw(
        CrosschainWithdrawData calldata data,
        CrosschainProofLib.CrosschainWithdrawProof calldata proof
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (data.feeRecipient != address(this)) revert WrongFeeRecipient();

        if (POOL_DIAMOND.withdrawalInputSettler() == address(0)) revert WithdrawalInputSettlerNotSet();

        uint256 scope = POOL_DIAMOND.SCOPE();

        uint32 chainId = uint32(uint256(data.encodedDestination) >> 224);
        (bool isConfigured,,,,,) = POOL_DIAMOND.withdrawalChainConfig(chainId);
        if (!isConfigured) revert DestinationChainNotConfigured();

        uint256 relayFeeBPS = proof.relayFeeBPS();
        (, , uint256 maxRelayFeeBPS) = POOL_DIAMOND.assetConfig();
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        uint256 maxSolver = POOL_DIAMOND.maxSolverFeeBPS();
        if (maxSolver == 0) revert MaxSolverFeeBPSNotSet();
        if (data.solverFeeBPS > maxSolver) revert SolverFeeGreaterThanMax();

        uint256 maxRefund = POOL_DIAMOND.maxRefundFeeBPS();
        if (maxRefund == 0) revert MaxRefundFeeBPSNotSet();
        uint256 refundFeeBPS = proof.refundFeeBPS();
        if (refundFeeBPS == 0) revert RefundFeeBPSZero();
        if (refundFeeBPS > maxRefund) revert RefundFeeGreaterThanMax();

        if (!_validateCrosschainWithdrawProof(abi.encode(data), proof, scope)) {
            revert CrosschainWithdrawalValidationFailed();
        }

        uint256 withdrawnValue = proof.withdrawnValue();
        address withdrawalRecipient = address(uint160(uint256(data.encodedDestination)));

        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, withdrawalRecipient)
        }

        if (relayFeeBPS == 0) revert ZeroFeeNotAllowed();
    }

    /**
     * @notice Internal validator for refund intents
     * @dev Called via self-call to validate refund intent and store results in transient storage
     */
    function refund(ShinobiIntent calldata intent) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();

        bytes32 orderId = intent.orderIdentifier();
        if (INPUT_SETTLER.orderStatus(orderId) != IShinobiInputSettler.OrderStatus.Deposited) {
            revert InvalidOrderStatus();
        }

        (address refundTarget, bytes memory handleRefundCalldata) = abi.decode(
            intent.refundCalldata,
            (address, bytes)
        );

        if (refundTarget != address(POOL_DIAMOND)) revert InvalidRefundTarget();

        address feeRecipient;
        uint256 refundFeeBPS;
        uint256 scope;
        assembly {
            let dataPtr := add(handleRefundCalldata, 32)
            feeRecipient := mload(add(dataPtr, 36))
            refundFeeBPS := mload(add(dataPtr, 68))
            scope := mload(add(dataPtr, 100))
        }

        if (feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != POOL_DIAMOND.SCOPE()) revert InvalidScope();
        if (refundFeeBPS == 0) revert ZeroFeeNotAllowed();

        uint256 escrowAmount = intent.inputs[0][1];
        uint256 expectedFeeAmount = (escrowAmount * refundFeeBPS) / 10_000;

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
        OperationType opType = abi.decode(context, (OperationType));

        uint256 postOpCost = MIN_POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualCost = actualGasCost + postOpCost;

        if (opType == OperationType.Withdrawal) {
            (, bytes32 userOpHash, address withdrawalRecipient, uint256 expectedFeeAmount) =
                abi.decode(context, (OperationType, bytes32, address, uint256));

            if (expectedFeeAmount > 0) {
                entryPoint.depositTo{value: expectedFeeAmount}(address(this));
            }

            emit CrosschainWithdrawalSponsored(
                withdrawalRecipient, userOpHash, actualCost,
                mode == IPaymaster.PostOpMode.opSucceeded
            );
        } else if (opType == OperationType.Refund) {
            (, bytes32 userOpHash, bytes32 orderId, uint256 expectedFeeAmount) =
                abi.decode(context, (OperationType, bytes32, bytes32, uint256));

            if (expectedFeeAmount > 0) {
                entryPoint.depositTo{value: expectedFeeAmount}(address(this));
            }

            emit RefundSponsored(
                orderId, userOpHash, actualCost,
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
        if (expectedSmartAccount == address(0)) revert ExpectedSmartAccountNotSet();
        if (userOp.sender != expectedSmartAccount) revert UnauthorizedSmartAccount();
        if (userOp.initCode.length > 0) revert SmartAccountNotDeployed();
        if (userOp.unpackPostOpGasLimit() < MIN_POST_OP_GAS_LIMIT) revert InsufficientPostOpGasLimit();

        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);

        if (target == address(POOL_DIAMOND)) {
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
        validationData = 0;
    }

    function _handleRefundValidation(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory context, uint256 validationData) {
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT_REFUND) revert InsufficientCallGasLimit();
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_VERIFICATION_GAS_REFUND) {
            revert InsufficientPaymasterVerificationGas();
        }

        if (value != 0) revert RefundValidationFailed();

        (bool success,) = address(this).call(data);
        if (!success) revert RefundValidationFailed();

        bytes32 orderId;
        uint256 expectedFeeAmount;
        uint32 intentExpires;
        assembly {
            orderId := tload(3)
            expectedFeeAmount := tload(4)
            intentExpires := tload(5)
            tstore(3, 0)
            tstore(4, 0)
            tstore(5, 0)
        }

        if (expectedFeeAmount < maxCost) revert InsufficientPaymasterCost();

        context = abi.encode(OperationType.Refund, userOpHash, orderId, expectedFeeAmount);

        uint48 validAfter = uint48(intentExpires);
        uint48 validUntil = 0;
        bool sigFailed = false;
        validationData = _packValidationData(sigFailed, validUntil, validAfter);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateCrosschainWithdrawal(
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        if (value != 0) return false;

        (bool success, ) = address(this).call(data);
        return success;
    }

    function _validateCrosschainWithdrawProof(
        bytes memory withdrawalData,
        CrosschainProofLib.CrosschainWithdrawProof memory proof,
        uint256 scope
    ) internal view returns (bool) {
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawalData, scope))
        ) % (Constants.SNARK_SCALAR_FIELD);

        if (proof.context() != expectedContext) return false;

        uint32 maxDepth = POOL_DIAMOND.MAX_TREE_DEPTH();
        if (proof.stateTreeDepth() > maxDepth || proof.ASPTreeDepth() > maxDepth) return false;

        if (!_isKnownRoot(proof.stateRoot())) return false;
        if (proof.ASPRoot() != POOL_DIAMOND.latestRoot()) return false;
        if (POOL_DIAMOND.nullifierHashes(proof.existingNullifierHash())) return false;
        if (proof.refundCommitment() == 0) return false;

        if (!CROSSCHAIN_VERIFIER.verifyProof(
            proof.pA, proof.pB, proof.pC, proof.pubSignals
        )) return false;

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _isKnownRoot(uint256 _root) internal view returns (bool) {
        if (_root == 0) return false;

        uint32 _index = POOL_DIAMOND.currentRootIndex();
        uint32 historySize = POOL_DIAMOND.ROOT_HISTORY_SIZE();

        for (uint32 _i = 0; _i < historySize; _i++) {
            if (_root == POOL_DIAMOND.roots(_index)) return true;
            _index = (_index + historySize - 1) % historySize;
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
