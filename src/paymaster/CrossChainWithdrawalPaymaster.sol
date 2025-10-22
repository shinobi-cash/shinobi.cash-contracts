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
import {IShinobiCashPool} from "../core/interfaces/IShinobiCashPool.sol";
import {ICrossChainWithdrawalVerifier} from "../core/interfaces/ICrossChainWithdrawalVerifier.sol";
import {CrossChainProofLib} from "../core/libraries/CrossChainProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title CrossChainWithdrawalPaymaster  
 * @notice ERC-4337 Paymaster for Cross-Chain Privacy Pool withdrawals
 * @dev This paymaster performs comprehensive validation using embedded cross-chain withdrawal validation
 *      to ensure it only sponsors successful privacy pool withdrawals. It validates ZK proofs,
 *      economics, and withdrawal parameters before sponsoring UserOperations.
 */
contract CrossChainWithdrawalPaymaster is BasePaymaster {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Return value for signature validation failures only
    uint256 internal constant _VALIDATION_FAILED = 1;

    /// @notice Cross-Chain Handler contract (ShinobiCashEntrypoint)
    IShinobiCashEntrypoint public immutable SHINOBI_CASH_ENTRYPOINT;

    /// @notice Cross-Chain Privacy Pool contract
    IShinobiCashPool public immutable ETH_POOL;

    /// @notice Expected smart account address for deterministic account pattern
    address public expectedSmartAccount;

    /// @notice Estimated gas cost for postOp operations
    uint256 public constant POST_OP_GAS_LIMIT = 32000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CrossChainWithdrawalSponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded
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

    /**
     * @notice Deploy Cross-Chain Withdrawal Paymaster
     * @param _entryPoint ERC-4337 EntryPoint contract
     * @param _shinobiCashEntrypoint Shinobi Cash Entrypoint contract
     * @param _ethShinobiCashPool ShinobiCash Pool contract
     */
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethShinobiCashPool
    ) BasePaymaster(_entryPoint) {
        SHINOBI_CASH_ENTRYPOINT = _shinobiCashEntrypoint;
        ETH_POOL = _ethShinobiCashPool;
    }

    /*//////////////////////////////////////////////////////////////
                               RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH from cross-chain fees and refunds
     */
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        SMART ACCOUNT CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the expected smart account address for deterministic account pattern
     * @dev Only owner can set this. Must be set before processing UserOperations.
     * @param account The smart account address that all UserOperations must come from
     */
    function setExpectedSmartAccount(address account) external onlyOwner {
        if (account == address(0)) {
            revert InvalidProcessooor();
        }
        
        address previousAccount = expectedSmartAccount;
        expectedSmartAccount = account;
        
        emit ExpectedSmartAccountUpdated(previousAccount, account);
    }

    /*//////////////////////////////////////////////////////////////
                        EMBEDDED WITHDRAWAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal relay method that mirrors ShinobiCashEntrypoint.processCrossChainWithdrawal()
     * @dev This method is called internally by the paymaster to validate withdrawal proofs
     *      without actually executing the withdrawal. It performs the same validation as
     *      the real Cross-Chain Handler but stores results in transient storage for economic checks.
     *      
     * @param withdrawal The cross-chain withdrawal parameters to validate
     * @param proof The ZK cross-chain withdrawal proof
     * @param scope The scope identifier for the privacy pool
     */
    function processCrossChainWithdrawal(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof calldata proof,
        uint256 scope,
        IShinobiCashCrossChainHandler.CrossChainIntentParams calldata /* intentParams */
    ) external {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller();
        }
        
        // Validate withdrawal targets the correct processooor (SHINOBI_CASH_ENTRYPOINT)
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) {
            revert InvalidProcessooor();
        }
        
        // Decode and validate relay data structure
        IShinobiCashCrossChainHandler.CrossChainRelayData memory relayData = abi.decode(
            withdrawal.data,
            (IShinobiCashCrossChainHandler.CrossChainRelayData)
        );
        
        // Ensure this paymaster receives the relay fees
        if (relayData.feeRecipient != address(this)) {
            revert WrongFeeRecipient();
        }
        
        // Validate scope matches our supported Cross-Chain Privacy Pool
        if (scope != ETH_POOL.SCOPE()) {
            revert InvalidScope();
        }

        // CRITICAL: Verify ZK proof to ensure withdrawal is valid
        if (!_validateCrossChainWithdrawCall(withdrawal, proof)) {
            revert CrossChainWithdrawalValidationFailed();
        }

        // Store decoded values in transient storage for economic validation
        uint256 withdrawnValue = proof.withdrawnValue(); // withdrawnValue from 9-signal proof
        uint256 relayFeeBPS = relayData.relayFeeBPS;
        
        // Extract recipient from encoded destination
        address withdrawalRecipient = address(uint160(uint256(relayData.encodedDestination)));

        // Store in transient storage (EIP-1153)
        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
            tstore(2, withdrawalRecipient)
        }
        
        // Ensure non-zero fees to prevent free withdrawals
        if (relayFeeBPS == 0) {
            revert ZeroFeeNotAllowed();
        }
    }
    /*//////////////////////////////////////////////////////////////
                            POST-OP OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle post-operation gas cost calculation and refunds
     * @dev Called after UserOperation execution to calculate actual costs and refund excess
     * @param context Encoded context from validation containing user info and expected costs
     * @param actualGasCost Actual gas cost of the UserOperation
     * @param actualUserOpFeePerGas Gas price paid by the UserOperation
     */
    function _postOp(
        IPaymaster.PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        // Decode context from validation phase
        (bytes32 userOpHash, address withdrawalRecipient, ) = abi
            .decode(context, (bytes32, address, uint256));

        // Calculate total actual cost including postOp overhead
        uint256 postOpCost = POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualWithdrawalCost = actualGasCost + postOpCost;

        // Emit withdrawal tracking event
        emit CrossChainWithdrawalSponsored(
            withdrawalRecipient,
            userOpHash,
            actualWithdrawalCost,
            0
        );
    }

    /*//////////////////////////////////////////////////////////////
                          PAYMASTER VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate a UserOperation for Cross-Chain Privacy Pool withdrawal
     * @dev Performs comprehensive validation including ZK proof verification, economics validation,
     *      and withdrawal parameter checks to ensure the paymaster only sponsors successful withdrawals
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @param maxCost Maximum gas cost the paymaster might pay
     * @return context Encoded context with user info and expected costs for postOp
     * @return validationData 0 if valid, packed failure data otherwise
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        // 1. Check that expected smart account is configured
        if (expectedSmartAccount == address(0)) {
            revert ExpectedSmartAccountNotSet();
        }
        
        // 2. Check that UserOperation comes from expected smart account
        if (userOp.sender != expectedSmartAccount) {
            revert UnauthorizedSmartAccount();
        }
        
        // 3. Ensure smart account is already deployed (no initCode)
        if (userOp.initCode.length > 0) {
            revert SmartAccountNotDeployed();
        }
        
        // 4. Check post-op gas limit is sufficient
        if (userOp.unpackPostOpGasLimit() < POST_OP_GAS_LIMIT) {
            revert InsufficientPostOpGasLimit();
        }
        
        // 5. Direct callData validation for SimpleAccount.execute()
        (address target, uint256 value, bytes memory data) = _extractExecuteCall(userOp.callData);
        
        // 6. Validate cross-chain withdrawal logic
        if (!_validateCrossChainWithdrawal(target, value, data)) {
            revert CrossChainWithdrawalValidationFailed();
        }
        
        // 7. Validate economics using values from transient storage
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        address withdrawalRecipient;
        assembly {
            withdrawnValue := tload(0)
            relayFeeBPS := tload(1)
            withdrawalRecipient := tload(2)
        }
        
        uint256 expectedFeeAmount = (withdrawnValue * relayFeeBPS) / 10_000;
        
        // Ensure paymaster receives enough fees to cover gas costs
        if (expectedFeeAmount < maxCost) {
            revert InsufficientPaymasterCost();
        }
        
        // Clear transient storage for composability
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

    /**
     * @notice Validate Cross-Chain Privacy Pool withdrawal by performing embedded proof verification
     * @dev This method validates the target and value, then calls the internal relay method
     *      to perform comprehensive ZK proof validation. This embedded validation approach
     *      allows the paymaster to verify withdrawal validity without external dependencies.
     *      
     * @param target The target address being called (should be Cross-Chain Handler)
     * @param value ETH value being sent (should be 0 for withdrawals)
     * @param data The call data to the Cross-Chain Handler
     * @return true if validation passes, false otherwise
     */
    function _validateCrossChainWithdrawal(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        // Validate target is Cross-Chain Handler
        if (target != address(SHINOBI_CASH_ENTRYPOINT)) {
            return false;
        }
        
         // Validate no ETH transfer
        if (value != 0) {
            return false;
        }
        
        // Direct call to processCrossChainWithdrawal method - let Solidity's dispatcher handle parameter decoding
        // This is more gas efficient than manually decoding parameters
        (bool success, ) = address(this).call(data);
        return success;
    }

    /*//////////////////////////////////////////////////////////////
                         CROSS-CHAIN PROOF VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate cross-chain withdrawal proof (mirrors Cross-Chain Handler logic)
     * @dev Performs comprehensive validation of the enhanced 9-signal ZK proof
     * @param withdrawal The cross-chain withdrawal parameters
     * @param proof The enhanced ZK proof with refund commitment
     * @return true if proof is valid, false otherwise
     */
    function _validateCrossChainWithdrawCall(
        IPrivacyPool.Withdrawal memory withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof memory proof
    ) internal view returns (bool) {
        // 1. Validate withdrawal context matches proof
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_POOL.SCOPE()))
        ) % (Constants.SNARK_SCALAR_FIELD);
        
        if (proof.context() != expectedContext) { 
            return false;
        }

        // 2. Check the tree depth signals are less than the max tree depth
        if (
            proof.stateTreeDepth() > ETH_POOL.MAX_TREE_DEPTH() || // stateTreeDepth
            proof.ASPTreeDepth() > ETH_POOL.MAX_TREE_DEPTH()    // ASPTreeDepth
        ) {
            return false;
        }

        // 3. Check state root is valid (same as _isKnownRoot in State.sol)
        uint256 stateRoot = proof.stateRoot();
        if (!_isKnownRoot(stateRoot)) {
            return false;
        }

        // 4. Validate ASP root is latest (same as PrivacyPool validation)
        uint256 aspRoot = proof.ASPRoot();
        if (aspRoot != SHINOBI_CASH_ENTRYPOINT.latestRoot()) {
            return false;
        }

        // 5. Check nullifier hasn't been spent
        uint256 nullifierHash = proof.existingNullifierHash(); // existingNullifierHash
        if (ETH_POOL.nullifierHashes(nullifierHash)) {
            return false;
        }

        // 6. Verify refund commitment is present (9th signal - cross-chain specific)
        if (proof.refundCommitmentHash() == 0) { // refundCommitmentHash
            return false;
        }

        // 7. Verify Groth16 proof with cross-chain withdrawal verifier
        if (
            !ICrossChainWithdrawalVerifier(ETH_POOL.crossChainVerifier()).verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                proof.pubSignals
            )
        ) {
            return false;
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a root is known/valid (mirrors State._isKnownRoot)
     * @param _root The root to validate
     * @return True if the root is in the last ROOT_HISTORY_SIZE roots
     */
    function _isKnownRoot(uint256 _root) internal view returns (bool) {
        if (_root == 0) return false;

        // Start from the most recent root (current index)
        uint32 _index = ETH_POOL.currentRootIndex();
        uint32 ROOT_HISTORY_SIZE = ETH_POOL.ROOT_HISTORY_SIZE();

        // Check all possible roots in the history
        for (uint32 _i = 0; _i < ROOT_HISTORY_SIZE; _i++) {
            if (_root == ETH_POOL.roots(_index)) return true;
            _index = (_index + ROOT_HISTORY_SIZE - 1) % ROOT_HISTORY_SIZE;
        }

        return false;
    }

    /**
     * @notice Extract target, value and data from SimpleAccount.execute() calldata
     * @param callData The full calldata from UserOperation
     * @return target The target address
     * @return value The ETH value  
     * @return data The call data
     */
    function _extractExecuteCall(bytes calldata callData) 
        internal 
        pure 
        returns (address target, uint256 value, bytes memory data) 
    {
        if (callData.length < 4) {
            revert InvalidCallData();
        }
        
        // Check for SimpleAccount.execute(address,uint256,bytes) selector
        bytes4 selector = bytes4(callData[:4]);
        bytes4 expectedSelector = 0xb61d27f6; // execute(address,uint256,bytes)
        
        if (selector != expectedSelector) {
            revert InvalidCallData();
        }
        
        // Decode parameters
        (target, value, data) = abi.decode(callData[4:], (address, uint256, bytes));
    }

}