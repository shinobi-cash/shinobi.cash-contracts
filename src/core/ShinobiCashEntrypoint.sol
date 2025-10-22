// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {Entrypoint} from "contracts/Entrypoint.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {ShinobiCashPool} from "./ShinobiCashPool.sol";
import {ShinobiCashPoolSimple} from "./implementations/ShinobiCashPoolSimple.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IShinobiCashCrossChainHandler} from "./interfaces/IShinobiCashCrossChainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashEntrypoint
 * @notice Extends Entrypoint with cross-chain withdrawal capabilities
 */
contract ShinobiCashEntrypoint is Entrypoint, IShinobiCashCrossChainHandler {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping of chain IDs to their support status
    mapping(uint256 chainId => bool isSupported) public supportedChains;


    /// @notice Address of the ShinobiInputSettler for cross-chain withdrawals
    address public inputSettler;

    /// @notice Address of the ShinobiOutputSettler for cross-chain operations
    address public outputSettler;

    /// @notice Intent oracle address (for deposits - not used for withdrawals)
    address public intentOracle;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when a chain's support status is updated
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);

    /// @notice Emitted when the ShinobiInputSettler address is updated
    /// @param previousInputSettler The previous ShinobiInputSettler address
    /// @param newInputSettler The new ShinobiInputSettler address
    event InputSettlerUpdated(address indexed previousInputSettler, address indexed newInputSettler);

    /// @notice Emitted when the ShinobiOutputSettler address is updated
    /// @param previousOutputSettler The previous ShinobiOutputSettler address
    /// @param newOutputSettler The new ShinobiOutputSettler address
    event OutputSettlerUpdated(address indexed previousOutputSettler, address indexed newOutputSettler);

    /// @notice Emitted when the intent oracle address is updated
    /// @param previousIntentOracle The previous intent oracle address
    /// @param newIntentOracle The new intent oracle address
    event IntentOracleUpdated(address indexed previousIntentOracle, address indexed newIntentOracle);

    /// @notice Emitted when a cross-chain refund is processed
    event RefundProcessed(
        uint256 amount,
        uint256 indexed refundCommitmentHash
    );

    /// @notice Emitted when a user initiates a cross-chain withdrawal
    /// @param withdrawer The address initiating the withdrawal
    /// @param nullifierHash The nullifier hash being spent
    /// @param recipient The final recipient on destination chain
    /// @param netAmount The net amount after fees
    /// @param destinationChainId The destination chain where withdrawal will be settled
    /// @param orderId The unique order identifier for tracking (links to InputSettler.Open event)
    event CrossChainWithdrawalIntent(
        address indexed withdrawer,
        uint256 indexed nullifierHash,
        address recipient,
        uint256 netAmount,
        uint256 destinationChainId,
        bytes32 indexed orderId
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when destination chain is not supported for cross-chain operations
    error DestinationChainNotSupported();

    /// @notice Thrown when pool does not support cross-chain operations
    error PoolDoesNotSupportCrossChain();

    /// @notice Thrown when relay fee exceeds the maximum allowed fee
    error RelayFeeExceedsMaximum();

    /// @notice Thrown when ShinobiInputSettler address is not set
    error InputSettlerNotSet();

    /// @notice Thrown when ShinobiOutputSettler address is not set
    error OutputSettlerNotSet();

    /// @notice Thrown when setter is called with zero address
    error InvalidAddress();

    /// @notice Thrown when caller is not the configured ShinobiInputSettler
    error OnlyInputSettler();

    /// @notice Thrown when caller is not the configured ShinobiOutputSettler
    error OnlyOutputSettler();

    /// @notice Thrown when ETH amount sent doesn't match the expected amount
    error AmountMismatch();

    /// @notice Thrown when deposit amount is below minimum required
    error BelowMinimumDeposit();


    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update the support status for a chain
    /// @param chainId The chain ID to update
    /// @param supported Whether the chain is supported
    function updateChainSupport(uint256 chainId, bool supported) external onlyRole(_OWNER_ROLE) {
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /// @notice Set the ShinobiInputSettler address
    /// @param _inputSettler The address of the ShinobiInputSettler contract
    function setInputSettler(address _inputSettler) external onlyRole(_OWNER_ROLE) {
        if (_inputSettler == address(0)) revert InvalidAddress();
        address previousInputSettler = inputSettler;
        inputSettler = _inputSettler;
        emit InputSettlerUpdated(previousInputSettler, _inputSettler);
    }

    /// @notice Set the ShinobiOutputSettler address
    /// @param _outputSettler The address of the ShinobiOutputSettler contract
    function setOutputSettler(address _outputSettler) external onlyRole(_OWNER_ROLE) {
        if (_outputSettler == address(0)) revert InvalidAddress();
        address previousOutputSettler = outputSettler;
        outputSettler = _outputSettler;
        emit OutputSettlerUpdated(previousOutputSettler, _outputSettler);
    }

    /// @notice Set the intent oracle address (used for deposits, not withdrawals)
    /// @param _intentOracle The address of the intent oracle contract
    function setIntentOracle(address _intentOracle) external onlyRole(_OWNER_ROLE) {
        address previousIntentOracle = intentOracle;
        intentOracle = _intentOracle;
        emit IntentOracleUpdated(previousIntentOracle, _intentOracle);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IShinobiCashCrossChainHandler
    function processCrossChainWithdrawal(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof calldata proof,
        uint256 scope,
        CrossChainIntentParams calldata intentParams
    ) external override nonReentrant {
        // CRITICAL: Validate ShinobiInputSettler is configured
        if (inputSettler == address(0)) revert InputSettlerNotSet();

        CrossChainRelayData memory relayData = abi.decode(withdrawal.data, (CrossChainRelayData));
        uint256 destinationChain = uint256(relayData.encodedDestination) >> 224;

        // SECURITY: Validate destination chain is supported
        if (!supportedChains[destinationChain]) revert DestinationChainNotSupported();

        // Get and validate privacy pool
        ShinobiCashPool shinobiPool = ShinobiCashPool(address(scopeToPool[scope]));
        if (address(shinobiPool) == address(0)) revert PoolNotFound();
        if (!shinobiPool.supportsCrossChain()) revert PoolDoesNotSupportCrossChain();

        // SECURITY: Validate relay fee doesn't exceed configured maximum
        IERC20 asset = IERC20(shinobiPool.ASSET());
        if (relayData.relayFeeBPS > assetConfig[asset].maxRelayFeeBPS) {
            revert RelayFeeExceedsMaximum();
        }

        // Execute privacy pool cross-chain withdrawal (validates ZK proof)
        shinobiPool.crossChainWithdraw(withdrawal, proof);

        // Calculate amounts and transfer fee if needed
        uint256 withdrawnAmount = proof.withdrawnValue();
        uint256 feeAmount = (withdrawnAmount * relayData.relayFeeBPS) / 10000;
        uint256 netAmount = withdrawnAmount - feeAmount;

        if (feeAmount > 0) {
            _transfer(asset, relayData.feeRecipient, feeAmount);
        }

        // Step 1: Create withdrawal intent
        ShinobiIntent memory intent = _createWithdrawalIntent(
            intentParams,
            bytes32(proof.existingNullifierHash()),
            bytes32(proof.pubSignals[8]), // refundCommitmentHash
            netAmount,
            scope
        );

        // Step 2: Submit intent and emit tracking event
        _submitIntent(
            intent,
            netAmount,
            msg.sender, // withdrawer
            address(uint160(uint256(relayData.encodedDestination))), // recipient
            destinationChain // destination chain ID
        );
    }
    

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the ShinobiInputSettler
     * @dev Forwards ETH to privacy pool for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund (from 9th signal of original proof)
     * @param _amount The amount being refunded (escrowed amount from OIF)
     * @param _scope The privacy pool scope identifier
     */
    function handleRefund(
        uint256 _refundCommitmentHash,
        uint256 _amount,
        uint256 _scope
    ) external payable  {
        // CRITICAL: Only ShinobiInputSettler can call this function
        // This ensures refunds are only processed for legitimate expired intents
        if (msg.sender != inputSettler) revert OnlyInputSettler();

        // SECURITY: Validate ETH amount matches refund amount
        if (msg.value != _amount) revert AmountMismatch();

        // Get the privacy pool for this scope
        IPrivacyPool basePool = scopeToPool[_scope];
        if (address(basePool) == address(0)) revert PoolNotFound();

        // Forward ETH to privacy pool for refund commitment insertion
        // Pool will insert refund commitment into merkle tree for later withdrawal
        ShinobiCashPool shinobiPool = ShinobiCashPool(address(basePool));
        shinobiPool.handleRefund{value: msg.value}(_refundCommitmentHash, _amount);

        emit RefundProcessed(_amount, _refundCommitmentHash);
    }

    /// @inheritdoc IShinobiCashCrossChainHandler
    function isChainSupported(uint256 chainId) external view override returns (bool) {
        return supportedChains[chainId];
    }

    /**
     * @notice Process a cross-chain deposit with verified depositor address
     * @dev Called by ShinobiOutputSettler after intent proof validation
     * @dev CRITICAL: depositor parameter comes from VERIFIED intent.user via intent proof
     * @param depositor The verified depositor address from origin chain
     * @param amount The deposit amount
     * @param precommitment The precommitment for the deposit
     */
    function processCrossChainDeposit(
        address depositor,
        uint256 amount,
        uint256 precommitment
    ) external payable nonReentrant {
        // CRITICAL: Only ShinobiOutputSettler can call this
        // This ensures the depositor was verified via intent proof on origin chain
        // Without this check, attacker could spoof depositor address
        if (msg.sender != outputSettler) revert OnlyOutputSettler();

        // SECURITY: Validate ETH amount matches deposit amount
        if (msg.value != amount) revert AmountMismatch();

        // Get the native ETH pool configuration
        IERC20 asset = IERC20(Constants.NATIVE_ASSET);
        AssetConfig memory config = assetConfig[asset];
        IPrivacyPool pool = config.pool;
        if (address(pool) == address(0)) revert PoolNotFound();

        // SECURITY: Check if the precommitment has already been used (prevent double-deposit)
        if (usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        usedPrecommitments[precommitment] = true;

        // SECURITY: Validate deposit meets minimum amount requirement
        if (amount < config.minimumDepositAmount) revert BelowMinimumDeposit();

        // Deduct vetting fees from deposit
        uint256 amountAfterFees = _deductFee(amount, config.vettingFeeBPS);

        // Deposit to pool with VERIFIED depositor address
        // This maintains ASP (Address Screening Protocol) compliance
        // The depositor address was cryptographically verified via intent proof
        uint256 commitment = pool.deposit{value: amountAfterFees}(depositor, amountAfterFees, precommitment);

        emit Deposited(depositor, pool, commitment, amountAfterFees);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create ShinobiIntent for withdrawal
     * @param intentParams User-provided validated intent parameters
     * @param nullifierHash The nullifier hash from privacy pool withdrawal
     * @param refundCommitmentHash The commitment hash for refund recovery
     * @param netAmount The net amount after fees
     * @param scope The privacy pool scope identifier
     * @return intent The created ShinobiIntent
     */
    function _createWithdrawalIntent(
        CrossChainIntentParams calldata intentParams,
        bytes32 nullifierHash,
        bytes32 refundCommitmentHash,
        uint256 netAmount,
        uint256 scope
    ) internal view returns (ShinobiIntent memory intent) {
        // Create refund calldata for returning to pool as commitment
        bytes memory refundCalldata = abi.encode(
            address(this), // target: ShinobiCashEntrypoint
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(refundCommitmentHash), // refund commitment hash
                netAmount,                     // refund amount
                scope                          // privacy pool scope
            )
        );

        // Create ShinobiIntent for withdrawal
        intent = ShinobiIntent({
            user: address(this),                        // ShinobiCashEntrypoint creates the order
            nonce: uint256(nullifierHash),              // Use nullifier hash as nonce for uniqueness
            originChainId: block.chainid,               // Current chain (Arbitrum)
            expires: intentParams.expires,              // User-provided expiry
            fillDeadline: intentParams.fillDeadline,    // User-provided fill deadline
            fillOracle: intentParams.fillOracle,        // Fill proof oracle (destination → origin)
            inputs: intentParams.inputs,                // User-provided inputs
            outputs: intentParams.outputs,              // User-provided outputs
            intentOracle: address(0),                   // No intent verification needed for withdrawals
            refundCalldata: refundCalldata              // Custom refund logic
        });
    }

    /**
     * @notice Submit ShinobiIntent to InputSettler and emit tracking event
     * @param intent The withdrawal intent to submit
     * @param netAmount The net amount after fees (for ETH transfer)
     * @param withdrawer The address initiating the withdrawal
     * @param recipient The final recipient on destination chain
     * @param destinationChainId The destination chain ID
     */
    function _submitIntent(
        ShinobiIntent memory intent,
        uint256 netAmount,
        address withdrawer,
        address recipient,
        uint256 destinationChainId
    ) internal {
        // Calculate orderId using library (gas efficient)
        bytes32 orderId = intent.orderIdentifier();

        // Emit event for indexers to track withdrawal initiation
        emit CrossChainWithdrawalIntent(
            withdrawer,
            intent.nonce, // nullifierHash
            recipient,
            netAmount,
            destinationChainId,
            orderId
        );

        // Submit intent to ShinobiInputSettler
        // ShinobiInputSettler will emit Open(orderId, intent) event
        IShinobiInputSettler(inputSettler).open{value: netAmount}(intent);
    }
 
}
