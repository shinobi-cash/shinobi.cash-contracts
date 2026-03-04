// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {IPoolDiamond} from "../interfaces/IPoolDiamond.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IWithdraw2Verifier} from "../../core/interfaces/IWithdraw2Verifier.sol";
import {Withdraw2ProofLib} from "../../core/libraries/Withdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title DiamondWithdraw2Paymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for same-chain Withdraw2 (2:1 merge) via PoolDiamond
 * @dev Validates 9-signal ZK proofs with 2 nullifiers before sponsoring UserOperations
 */
contract DiamondWithdraw2Paymaster is BasePaymaster {
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MIN_POST_OP_GAS_LIMIT = 80_000;
    uint256 public constant MIN_CALL_GAS_LIMIT = 650_000;
    uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 500_000;

    IPoolDiamond public immutable POOL_DIAMOND;
    IWithdraw2Verifier public immutable WITHDRAW2_VERIFIER;
    address public expectedSmartAccount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Withdraw2Sponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
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
    error WithdrawalValidationFailed();
    error InsufficientPaymasterCost();
    error WrongFeeRecipient();
    error UnauthorizedCaller();
    error InvalidProcessooor();
    error ZeroFeeNotAllowed();
    error ExpectedSmartAccountNotSet();
    error UnauthorizedSmartAccount();
    error SmartAccountNotDeployed();
    error InvalidAddress();
    error RelayFeeGreaterThanMax();
    error InvalidRelayDataLength();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IPoolDiamond _poolDiamond,
        IWithdraw2Verifier _withdraw2Verifier
    ) BasePaymaster(_entryPoint) {
        if (address(_poolDiamond) == address(0)) revert InvalidAddress();
        if (address(_withdraw2Verifier) == address(0)) revert InvalidAddress();
        POOL_DIAMOND = _poolDiamond;
        WITHDRAW2_VERIFIER = _withdraw2Verifier;
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
                        EMBEDDED WITHDRAW2 VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal validation matching diamond's withdraw2() signature
     * @dev Called via self-call to leverage Solidity's built-in dispatcher
     */
    function withdraw2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        Withdraw2ProofLib.Withdraw2Proof calldata proof
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (withdrawal.processooor != address(POOL_DIAMOND)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        (address feeRecipient, uint256 relayFeeBPS, address recipient) = _decodeRelayData(withdrawal.data);

        if (feeRecipient != address(this)) revert WrongFeeRecipient();

        uint256 scope = POOL_DIAMOND.SCOPE();

        // Early relay fee validation
        (, , uint256 maxRelayFeeBPS) = POOL_DIAMOND.assetConfig();
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (!_validateWithdraw2Proof(withdrawal, proof, scope)) revert WithdrawalValidationFailed();

        uint256 withdrawnValue = proof.withdrawnValue();

        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, recipient)
        }

        if (relayFeeBPS == 0) revert ZeroFeeNotAllowed();
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
        (bytes32 userOpHash, address withdrawalRecipient, uint256 expectedFeeAmount) = abi
            .decode(context, (bytes32, address, uint256));

        uint256 postOpCost = MIN_POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualWithdrawalCost = actualGasCost + postOpCost;

        uint256 refundAmount = 0;
        bool executionSucceeded = mode == IPaymaster.PostOpMode.opSucceeded;

        if (executionSucceeded && expectedFeeAmount > actualWithdrawalCost) {
            refundAmount = expectedFeeAmount - actualWithdrawalCost;
            (bool success, ) = withdrawalRecipient.call{value: refundAmount}("");
            success;
        }

        if (actualWithdrawalCost > 0) {
            entryPoint.depositTo{value: actualWithdrawalCost}(address(this));
        }

        emit Withdraw2Sponsored(
            withdrawalRecipient,
            userOpHash,
            actualWithdrawalCost,
            refundAmount,
            executionSucceeded
        );
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
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT) revert InsufficientCallGasLimit();
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_PAYMASTER_VERIFICATION_GAS) {
            revert InsufficientPaymasterVerificationGas();
        }

        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);

        if (!_validateWithdraw2Withdrawal(target, value, data)) {
            revert WithdrawalValidationFailed();
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

        return (abi.encode(userOpHash, withdrawalRecipient, expectedFeeAmount), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateWithdraw2Withdrawal(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        if (target != address(POOL_DIAMOND)) return false;
        if (value != 0) return false;

        (bool success, ) = address(this).call(data);
        return success;
    }

    function _validateWithdraw2Proof(
        IPrivacyPool.Withdrawal memory withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory proof,
        uint256 scope
    ) internal view returns (bool) {
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, scope))
        ) % Constants.SNARK_SCALAR_FIELD;

        if (proof.context() != expectedContext) return false;

        uint32 maxDepth = POOL_DIAMOND.MAX_TREE_DEPTH();
        if (proof.stateTreeDepth() > maxDepth || proof.ASPTreeDepth() > maxDepth) return false;

        if (!_isKnownRoot(proof.stateRoot())) return false;
        if (proof.ASPRoot() != POOL_DIAMOND.latestRoot()) return false;
        if (POOL_DIAMOND.nullifierHashes(proof.nullifierHash0())) return false;
        if (POOL_DIAMOND.nullifierHashes(proof.nullifierHash1())) return false;

        if (!WITHDRAW2_VERIFIER.verifyProof(
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

    function _decodeRelayData(bytes memory data) internal pure returns (
        address feeRecipient,
        uint256 relayFeeBPS,
        address recipient
    ) {
        (recipient, feeRecipient, relayFeeBPS) = abi.decode(data, (address, address, uint256));
    }
}
