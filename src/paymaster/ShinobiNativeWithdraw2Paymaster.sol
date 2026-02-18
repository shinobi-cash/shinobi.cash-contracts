// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IShinobiCashEntrypoint} from "../core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../core/interfaces/IShinobiCashPool.sol";
import {IWithdraw2Verifier} from "../core/interfaces/IWithdraw2Verifier.sol";
import {Withdraw2ProofLib} from "../core/libraries/Withdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";

/**
 * @title ShinobiNativeWithdraw2Paymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for same-chain Withdraw2 (2:1 merge) operations
 * @dev Validates 9-signal ZK proofs with 2 nullifiers before sponsoring UserOperations
 */
contract ShinobiNativeWithdraw2Paymaster is BasePaymaster {
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MIN_POST_OP_GAS_LIMIT = 80_000;
    uint256 public constant MIN_CALL_GAS_LIMIT = 650_000;
    uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 500_000;

    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;
    IShinobiCashPool public immutable ETH_CASH_POOL;
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
    error InvalidScope();
    error ZeroFeeNotAllowed();
    error ExpectedSmartAccountNotSet();
    error UnauthorizedSmartAccount();
    error SmartAccountNotDeployed();
    error NullifierAlreadySpent();
    error InvalidWithdraw2Proof();
    error InvalidAddress();
    error RelayFeeGreaterThanMax();
    error InvalidRelayDataLength();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        IWithdraw2Verifier _withdraw2Verifier
    ) BasePaymaster(_entryPoint) {
        if (address(_shinobiCashEntrypoint) == address(0)) revert InvalidAddress();
        if (address(_ethCashPool) == address(0)) revert InvalidAddress();
        if (address(_withdraw2Verifier) == address(0)) revert InvalidAddress();
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_CASH_POOL = _ethCashPool;
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
        if (account == address(0)) {
            revert InvalidProcessooor();
        }

        address previousAccount = expectedSmartAccount;
        expectedSmartAccount = account;

        emit ExpectedSmartAccountUpdated(previousAccount, account);
    }

    /*//////////////////////////////////////////////////////////////
                        EMBEDDED WITHDRAW2 VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal relay method for Withdraw2 validation
     * @dev Called internally to validate Withdraw2 proofs and store results in transient storage
     */
    function relay2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        Withdraw2ProofLib.Withdraw2Proof calldata proof,
        uint256 scope
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        (address feeRecipient, uint256 relayFeeBPS, address recipient) = _decodeRelayData(withdrawal.data);

        if (feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early relay fee validation - fail fast before expensive ZK verification
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (!_validateWithdraw2Proof(withdrawal, proof)) revert WithdrawalValidationFailed();

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
            success; // Suppress unused variable warning
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
                        WITHDRAW2 VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateWithdraw2Withdrawal(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        if (target != address(SHINOBI_CASH_ENTRYPOINT)) return false;
        if (value != 0) return false;

        (bool success, ) = address(this).call(data);
        return success;
    }

    function _validateWithdraw2Proof(
        IPrivacyPool.Withdrawal memory withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory proof
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

        if (!WITHDRAW2_VERIFIER.verifyProof(
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
        if (callData.length < 4) {
            revert InvalidCallData();
        }

        bytes4 selector = bytes4(callData[:4]);
        if (selector != 0xb61d27f6) {
            revert InvalidCallData();
        }

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
