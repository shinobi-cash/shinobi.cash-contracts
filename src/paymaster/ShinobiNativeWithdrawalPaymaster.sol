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
import {IShinobiCashEntrypoint} from "../core/interfaces/IShinobiCashEntrypoint.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IWithdrawalVerifier} from "../core/interfaces/IWithdrawalVerifier.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";

/**
 * @title ShinobiNativeWithdrawalPaymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for same-chain privacy pool withdrawals
 * @dev Validates 8-signal ZK proofs and economics before sponsoring UserOperations
 */
contract ShinobiNativeWithdrawalPaymaster is BasePaymaster {
    using ProofLib for ProofLib.WithdrawProof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant _VALIDATION_FAILED = 1;
    uint256 public constant MIN_POST_OP_GAS_LIMIT = 80_000;
    uint256 public constant MIN_CALL_GAS_LIMIT = 550_000;
    uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 400_000;

    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;
    IPrivacyPool public immutable ETH_CASH_POOL;
    address public expectedSmartAccount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PrivacyPoolWithdrawalSponsored(
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
    error InvalidAddress();
    error RelayFeeGreaterThanMax();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IPrivacyPool _ethPrivacyPool
    ) BasePaymaster(_entryPoint) {
        if (address(_shinobiCashEntrypoint) == address(0)) revert InvalidAddress();
        if (address(_ethPrivacyPool) == address(0)) revert InvalidAddress();
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_CASH_POOL = _ethPrivacyPool;
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
     * @notice Internal relay method that mirrors Privacy Pool Entrypoint.relay()
     * @dev Called internally to validate withdrawal proofs and store results in transient storage
     */
    function relay(
        IPrivacyPool.Withdrawal calldata withdrawal,
        ProofLib.WithdrawProof calldata proof,
        uint256 scope
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();

        IEntrypoint.RelayData memory relayData = abi.decode(
            withdrawal.data,
            (IEntrypoint.RelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early relay fee validation - fail fast before expensive ZK verification
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayData.relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (!_validateWithdrawCall(withdrawal, proof)) revert WithdrawalValidationFailed();

        uint256 withdrawnValue = proof.withdrawnValue();
        uint256 relayFeeBPS = relayData.relayFeeBPS;
        address withdrawalRecipient = relayData.recipient;

        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, withdrawalRecipient)
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

        emit PrivacyPoolWithdrawalSponsored(
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

        if (!_validatePrivacyPoolWithdrawal(target, value, data)) {
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
                        EMBEDDED WITHDRAWAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validatePrivacyPoolWithdrawal(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        if (target != address(SHINOBI_CASH_ENTRYPOINT)) return false;
        if (value != 0) return false;

        (bool success, ) = address(this).call(data);
        return success;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _validateWithdrawCall(
        IPrivacyPool.Withdrawal memory withdrawal,
        ProofLib.WithdrawProof memory proof
    ) internal view returns (bool) {
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_CASH_POOL.SCOPE()))
        ) % (Constants.SNARK_SCALAR_FIELD);

        if (proof.context() != expectedContext) return false;

        if (
            proof.stateTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH() ||
            proof.ASPTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH()
        ) return false;

        if (!_isKnownRoot(proof.stateRoot())) return false;
        if (proof.ASPRoot() != SHINOBI_CASH_ENTRYPOINT.latestRoot()) return false;
        if (ETH_CASH_POOL.nullifierHashes(proof.existingNullifierHash())) return false;

        if (!IWithdrawalVerifier(address(ETH_CASH_POOL.WITHDRAWAL_VERIFIER())).verifyProof(
            proof.pA,
            proof.pB,
            proof.pC,
            proof.pubSignals
        )) return false;

        return true;
    }

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
