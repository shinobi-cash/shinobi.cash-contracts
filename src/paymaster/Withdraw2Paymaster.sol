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

/**
 * @title Withdraw2Paymaster
 * @notice ERC-4337 Paymaster for Shinobi Cash Pool Withdraw2 (2 inputs) withdrawals
 * @dev This paymaster validates Withdraw2 proofs (2 inputs, 1 output) before sponsoring
 *      UserOperations. It verifies both input nullifiers are unspent and the ZK proof is valid.
 */
contract Withdraw2Paymaster is BasePaymaster {
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Estimated gas cost for postOp operations
    uint256 public constant POST_OP_GAS_LIMIT = 100_000;

    /// @notice Minimum call gas limit to ensure Withdraw2 execution completes
    uint256 public constant MIN_CALL_GAS_LIMIT = 650_000;

    /// @notice Minimum paymaster verification gas limit
    uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 500_000;

    /// @notice Privacy Pool Entrypoint contract
    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;

    /// @notice ETH Cash Pool contract
    IShinobiCashPool public immutable ETH_CASH_POOL;

    /// @notice Withdraw2 verifier contract
    IWithdraw2Verifier public immutable WITHDRAW2_VERIFIER;

    /// @notice Expected smart account address for deterministic account pattern
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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy Withdraw2 Paymaster
     * @param _entryPoint ERC-4337 EntryPoint contract
     * @param _shinobiCashEntrypoint Shinobi Cash Entrypoint contract
     * @param _ethCashPool ETH Cash Pool contract (IShinobiCashPool)
     * @param _withdraw2Verifier Withdraw2 proof verifier
     */
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        IWithdraw2Verifier _withdraw2Verifier
    ) BasePaymaster(_entryPoint) {
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
     * @dev Called internally to validate Withdraw2 proofs before sponsoring
     * @param withdrawal The withdrawal parameters
     * @param proof The Withdraw2 proof (10 signals)
     * @param scope The scope identifier for the privacy pool
     */
    function relayWithdraw2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        Withdraw2ProofLib.Withdraw2Proof calldata proof,
        uint256 scope
    ) external {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller();
        }

        // Validate processooor
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) {
            revert InvalidProcessooor();
        }

        // Decode relay data
        (address feeRecipient, uint256 relayFeeBPS, address recipient) = _decodeRelayData(withdrawal.data);

        // Ensure this paymaster receives the relay fees
        if (feeRecipient != address(this)) {
            revert WrongFeeRecipient();
        }

        // Validate scope matches our ETH Cash Pool
        if (scope != ETH_CASH_POOL.SCOPE()) {
            revert InvalidScope();
        }

        // Validate the Withdraw2 proof
        if (!_validateWithdraw2Proof(withdrawal, proof)) {
            revert WithdrawalValidationFailed();
        }

        // Store values in transient storage for economic validation
        uint256 withdrawnValue = proof.withdrawnValue();

        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, recipient)
        }

        if (relayFeeBPS == 0) {
            revert ZeroFeeNotAllowed();
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
        (bytes32 userOpHash, address withdrawalRecipient, uint256 expectedFeeAmount) = abi
            .decode(context, (bytes32, address, uint256));

        uint256 postOpCost = POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
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
        // 1. Check expected smart account is configured
        if (expectedSmartAccount == address(0)) {
            revert ExpectedSmartAccountNotSet();
        }

        // 2. Check UserOperation comes from expected smart account
        if (userOp.sender != expectedSmartAccount) {
            revert UnauthorizedSmartAccount();
        }

        // 3. Ensure smart account is already deployed
        if (userOp.initCode.length > 0) {
            revert SmartAccountNotDeployed();
        }

        // 4. Check gas limits
        if (userOp.unpackPostOpGasLimit() < POST_OP_GAS_LIMIT) {
            revert InsufficientPostOpGasLimit();
        }
        if (userOp.unpackCallGasLimit() < MIN_CALL_GAS_LIMIT) {
            revert InsufficientCallGasLimit();
        }
        if (userOp.unpackPaymasterVerificationGasLimit() < MIN_PAYMASTER_VERIFICATION_GAS) {
            revert InsufficientPaymasterVerificationGas();
        }

        // 5. Extract execute call data
        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);

        // 6. Validate Withdraw2 withdrawal
        if (!_validateWithdraw2Withdrawal(target, value, data)) {
            revert WithdrawalValidationFailed();
        }

        // 7. Validate economics using transient storage
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        address withdrawalRecipient;
        assembly {
            withdrawnValue := tload(0)
            relayFeeBPS := tload(1)
            withdrawalRecipient := tload(2)
        }

        uint256 expectedFeeAmount = (withdrawnValue * relayFeeBPS) / 10_000;

        if (expectedFeeAmount < maxCost) {
            revert InsufficientPaymasterCost();
        }

        // Clear transient storage
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
        if (target != address(SHINOBI_CASH_ENTRYPOINT)) {
            return false;
        }

        if (value != 0) {
            return false;
        }

        // Call internal relayWithdraw2 method
        (bool success, ) = address(this).call(data);
        return success;
    }

    function _validateWithdraw2Proof(
        IPrivacyPool.Withdrawal memory withdrawal,
        Withdraw2ProofLib.Withdraw2Proof memory proof
    ) internal view returns (bool) {
        // 1. Validate context
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_CASH_POOL.SCOPE()))
        ) % Constants.SNARK_SCALAR_FIELD;

        if (proof.context() != expectedContext) {
            return false;
        }

        // 2. Check tree depths
        if (
            proof.stateTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH() ||
            proof.ASPTreeDepth() > ETH_CASH_POOL.MAX_TREE_DEPTH()
        ) {
            return false;
        }

        // 3. Check state root is valid
        if (!_isKnownRoot(proof.stateRoot())) {
            return false;
        }

        // 4. Validate ASP root is latest
        if (proof.ASPRoot() != SHINOBI_CASH_ENTRYPOINT.latestRoot()) {
            return false;
        }

        // 5. Check BOTH nullifiers haven't been spent (Withdraw2 specific)
        if (ETH_CASH_POOL.nullifierHashes(proof.nullifierHash0())) {
            return false;
        }
        if (ETH_CASH_POOL.nullifierHashes(proof.nullifierHash1())) {
            return false;
        }

        // 6. Verify Withdraw2 Groth16 proof
        if (!WITHDRAW2_VERIFIER.verifyProof(
            proof.pA,
            proof.pB,
            proof.pC,
            proof.pubSignals
        )) {
            return false;
        }

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
        // Decode RelayData structure from withdrawal.data
        // RelayData: { recipient, feeRecipient, relayFeeBPS }
        (recipient, feeRecipient, relayFeeBPS) = abi.decode(
            data,
            (address, address, uint256)
        );
    }
}
