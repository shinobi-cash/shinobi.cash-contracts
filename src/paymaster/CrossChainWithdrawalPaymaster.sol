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
import {IShinobiCashCrossChainHandler} from "../core/interfaces/IShinobiCashCrossChainHandler.sol";
import {ShinobiCashPool} from "../core/ShinobiCashPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "../core/interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {CrossChainProofLib} from "../core/libraries/CrossChainProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title CrossChainWithdrawalPaymaster
 * @author Karandeep Singh
 * @notice ERC-4337 Paymaster for cross-chain privacy pool withdrawals
 * @dev Validates 9-signal ZK proofs and economics before sponsoring UserOperations
 */
contract CrossChainWithdrawalPaymaster is BasePaymaster {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant _VALIDATION_FAILED = 1;
    uint256 public constant POST_OP_GAS_LIMIT = 100_000;
    uint256 public constant MIN_CALL_GAS_LIMIT = 687_500;
    uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 500_000;

    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;
    ShinobiCashPool public immutable ETH_POOL;
    address public expectedSmartAccount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CrossChainWithdrawalSponsored(
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
    error CrossChainWithdrawalValidationFailed();
    error InsufficientPaymasterCost();
    error WrongFeeRecipient();
    error UnauthorizedCaller();
    error InvalidProcessooor();
    error InvalidScope();
    error ZeroFeeNotAllowed();
    error ExpectedSmartAccountNotSet();
    error UnauthorizedSmartAccount();
    error SmartAccountNotDeployed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        ShinobiCashPool _ethShinobiCashPool
    ) BasePaymaster(_entryPoint) {
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_POOL = _ethShinobiCashPool;
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
        CrossChainProofLib.CrossChainWithdrawProof calldata _proof,
        uint256 _scope
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        if (_withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();

        IShinobiCashCrossChainHandler.CrossChainRelayData memory relayData = abi.decode(
            _withdrawal.data,
            (IShinobiCashCrossChainHandler.CrossChainRelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (_scope != ETH_POOL.SCOPE()) revert InvalidScope();
        if (!_validateCrossChainWithdrawCall(_withdrawal, _proof)) revert CrossChainWithdrawalValidationFailed();

        uint256 withdrawnValue = _proof.withdrawnValue();
        uint256 relayFeeBPS = relayData.relayFeeBPS;
        address withdrawalRecipient = address(uint160(uint256(relayData.encodedDestination)));

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

        uint256 postOpCost = POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualWithdrawalCost = actualGasCost + postOpCost;

        if (expectedFeeAmount > 0) {
            entryPoint.depositTo{value: expectedFeeAmount}(address(this));
        }

        emit CrossChainWithdrawalSponsored(
            withdrawalRecipient,
            userOpHash,
            actualWithdrawalCost,
            0,
            mode == IPaymaster.PostOpMode.opSucceeded
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
        if (userOp.unpackPostOpGasLimit() < POST_OP_GAS_LIMIT) revert InsufficientPostOpGasLimit();
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT) revert InsufficientCallGasLimit();
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_PAYMASTER_VERIFICATION_GAS) {
            revert InsufficientPaymasterVerificationGas();
        }

        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);

        if (!_validateCrossChainWithdrawal(target, value, data)) {
            revert CrossChainWithdrawalValidationFailed();
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

    function _validateCrossChainWithdrawal(
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
                         CROSS-CHAIN PROOF VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateCrossChainWithdrawCall(
        IPrivacyPool.Withdrawal memory withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory proof
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

        if (!ICrossChainWithdrawalProofVerifier(ETH_POOL.CROSS_CHAIN_WITHDRAWAL_VERIFIER()).verifyProof(
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