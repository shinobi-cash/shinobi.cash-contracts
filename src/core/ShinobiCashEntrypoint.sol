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
import {ShinobiCashCrosschainState} from "./ShinobiCashCrosschainState.sol";

/**
 * @title ShinobiCashEntrypoint
 * @notice Extends Entrypoint with cross-chain withdrawal capabilities
 * @dev Inherits cross-chain state from ShinobiCashCrosschainState
 */
contract ShinobiCashEntrypoint is Entrypoint, ShinobiCashCrosschainState, IShinobiCashCrossChainHandler {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Result data from processing a withdrawal intent
    struct WithdrawalResult {
        bytes32 orderId;       // Order identifier for tracking
        uint256 netAmount;     // Amount user receives on destination
        uint256 totalFees;     // Total fees (relay + solver)
    }

    /*//////////////////////////////////////////////////////////////
                               Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyWithdrawalInputSettler() {
        if (msg.sender != withdrawalInputSettler) revert OnlyWithdrawalInputSettler();
        _;
    }

    modifier onlyDepositOutputSettler() {
        if (msg.sender != depositOutputSettler) revert OnlyDepositOutputSettler();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Set the ShinobiInputSettler address for withdrawals
    /// @param _inputSettler The address of the ShinobiInputSettler contract
    function setWithdrawalInputSettler(address _inputSettler) external onlyRole(_OWNER_ROLE) {
        if (_inputSettler == address(0)) revert InvalidAddress();
        address previous = withdrawalInputSettler;
        withdrawalInputSettler = _inputSettler;
        emit WithdrawalInputSettlerUpdated(previous, _inputSettler);
    }

    /// @notice Set the ShinobiDepositOutputSettler address for deposits
    /// @param _outputSettler The address of the ShinobiDepositOutputSettler contract
    function setDepositOutputSettler(address _outputSettler) external onlyRole(_OWNER_ROLE) {
        if (_outputSettler == address(0)) revert InvalidAddress();
        address previous = depositOutputSettler;
        depositOutputSettler = _outputSettler;
        emit DepositOutputSettlerUpdated(previous, _outputSettler);
    }


    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure a destination chain for cross-chain withdrawals
    /// @param _chainId The destination chain ID
    /// @param _outputSettler The ShinobiWithdrawalOutputSettler address on destination chain
    /// @param _outputOracle The oracle address on destination chain
    /// @param _fillOracle The fill oracle address for validating fills
    /// @param _fillDeadline The default fill deadline in seconds (relative to block.timestamp)
    /// @param _expiry The default expiry in seconds (relative to block.timestamp)
    function setWithdrawalChainConfig(
        uint256 _chainId,
        address _outputSettler,
        address _outputOracle,
        address _fillOracle,
        uint32 _fillDeadline,
        uint32 _expiry
    ) external onlyRole(_OWNER_ROLE) {
        if (_outputSettler == address(0)) revert InvalidAddress();
        if (_outputOracle == address(0)) revert InvalidAddress();
        if (_fillOracle == address(0)) revert InvalidAddress();

        // Validate deadline minimums (at least 5 minutes = 300 seconds)
        if (_fillDeadline < 300) revert DeadlineTooShort();
        if (_expiry < 300) revert DeadlineTooShort();

        // Validate deadline ordering (expiry must be after fillDeadline)
        if (_expiry <= _fillDeadline) revert ExpiryBeforeFillDeadline();

        withdrawalChainConfig[_chainId] = WithdrawalChainConfig({
            isConfigured: true,
            withdrawalOutputSettler: _outputSettler,
            withdrawalFillOracle: _outputOracle,
            fillOracle: _fillOracle,
            fillDeadline: _fillDeadline,
            expiry: _expiry
        });

        emit WithdrawalChainConfigured(_chainId, _fillDeadline, _expiry, _outputSettler, _outputOracle, _fillOracle);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Handle a cross-chain deposit with verified depositor address
    function crosschainDeposit(address _depositor,
        uint256 _amount,
        uint256 _precommitment
        ) external override payable nonReentrant onlyDepositOutputSettler()  returns (uint256 _commitment) {
       
        if(msg.value != _amount) revert AmountMismatch();
        // Handle deposit as native asset
        _commitment = _handleCrosschainDeposit(IERC20(Constants.NATIVE_ASSET), _depositor, msg.value, _precommitment);
    }


    /// @inheritdoc IShinobiCashCrossChainHandler
    function crosschainWithdrawal(
          IPrivacyPool.Withdrawal calldata _withdrawal,
          CrossChainProofLib.CrossChainWithdrawProof calldata _proof,
          uint256 _scope
    ) external override nonReentrant {
        // CRITICAL: Validate ShinobiInputSettler is configured
        if (withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();

        // Check withdrawn amount is non-zero
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        // Check allowed processooor is this Entrypoint
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        // Fetch pool by scope
        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        // Store pool asset and balance
        IERC20 _asset = IERC20(_shinobiPool.ASSET());
        uint256 _balanceBefore = _assetBalance(_asset);

        CrossChainRelayData memory _data = abi.decode(_withdrawal.data, (CrossChainRelayData));

        // SECURITY: Validate destination chain is supported and configured
        if (!withdrawalChainConfig[uint256(_data.encodedDestination) >> 224].isConfigured) revert DestinationChainNotConfigured();

        if (_data.relayFeeBPS > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        // Execute privacy pool cross-chain withdrawal (validates ZK proof)
        _shinobiPool.crosschainWithdraw(_withdrawal, _proof);

        // Open withdrawal intent and get event data
        WithdrawalResult memory result = _openWithdrawalIntent(
            _asset,
            _proof.withdrawnValue(),
            _data,
            _scope,
            bytes32(_proof.existingNullifierHash()),
            bytes32(_proof.pubSignals[8])
        );

        // Check pool balance has not been reduced
        if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();

        // Emit event for indexers to track withdrawal initiation
        emit CrossChainWithdrawalIntentRelayed(
            msg.sender,
            _data.encodedDestination,
            _asset,
            result.netAmount,
            result.totalFees,
            result.orderId
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
    ) external payable onlyWithdrawalInputSettler()  {

        // SECURITY: Validate ETH amount matches refund amount
        if (msg.value != _amount) revert AmountMismatch();

        // Get the privacy pool for this scope
         ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        // Forward ETH to privacy pool for refund commitment insertion
        // Pool will insert refund commitment into merkle tree for later withdrawal
        _shinobiPool.handleRefund{value: msg.value}(_refundCommitmentHash, _amount);

        emit Refunded(_amount, _refundCommitmentHash);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _openWithdrawalIntent(
        IERC20 _asset,
        uint256 _withdrawnAmount,
        CrossChainRelayData memory _data,
        uint256 _scope,
        bytes32 _nullifierHash,
        bytes32 _refundCommitmentHash
    ) internal returns (WithdrawalResult memory result) {
        WithdrawalFees memory fees = _calculateWithdrawalFees(_withdrawnAmount, _data.relayFeeBPS, _data.solverFeeBPS);

        // Calculate amounts from withdrawn amount and fees
        uint256 _escrowAmount = _withdrawnAmount - fees.relayFee;           // Amount escrowed (includes solver fee)
        uint256 _netAmount = _withdrawnAmount - fees.relayFee - fees.solverFee;  // Amount user receives

        // Create withdrawal intent using CONFIGURED values
        ShinobiIntent memory intent = _createWithdrawalIntent(
            _nullifierHash,
            _refundCommitmentHash, // refundCommitmentHash
            _escrowAmount,                  // Amount escrowed in OIF (input)
            _netAmount,                     // Amount user receives (output)
            uint256(_data.encodedDestination) >> 224, // destinationChain
            _data.encodedDestination,
            _scope
        );

        // Transfer relay fee to fee recipient
        _transfer(_asset, _data.feeRecipient, fees.relayFee);

        // Submit intent to ShinobiInputSettler
        IShinobiInputSettler(withdrawalInputSettler).open{value: _escrowAmount}(intent);

        // Prepare result data for event emission
        result.orderId = intent.orderIdentifier();
        result.netAmount = _netAmount;
        result.totalFees = fees.relayFee + fees.solverFee;
    }

    /**
     * @notice Handle a cross-chain deposit with verified depositor address
     * @param _asset The asset being deposited
     * @param _depositor The verified depositor address from origin chain
     * @param _amount The deposit amount
     * @param _precommitment The precommitment for the deposit
     */
    function _handleCrosschainDeposit(
        IERC20 _asset,
        address _depositor,
        uint256 _amount,
        uint256 _precommitment
    ) internal returns (uint256 _commitment)  {
        // Fetch pool by asset
        AssetConfig memory config = assetConfig[_asset];
        IPrivacyPool pool = config.pool;
        if (address(pool) == address(0)) revert PoolNotFound();

        // Check if the `_precommitment` has already been used
        if (usedPrecommitments[_precommitment]) revert PrecommitmentAlreadyUsed();

        // Mark it as used
        usedPrecommitments[_precommitment] = true;

        // Check minimum deposit amount
        if (_amount < config.minimumDepositAmount) revert MinimumDepositAmount();

        // Deduct vetting fees
        uint256 _amountAfterFees = _deductFee(_amount, config.vettingFeeBPS);

        // Deposit commitment into pool (forwarding native asset if applicable)
        uint256 _nativeAssetValue = address(_asset) == Constants.NATIVE_ASSET ? _amountAfterFees : 0;
        _commitment = pool.deposit{value: _nativeAssetValue}(_depositor, _nativeAssetValue, _precommitment);

        emit CrosschainDeposited(_depositor, address(pool), _precommitment, _commitment, _amountAfterFees);
    }


    /**
     * @notice Create ShinobiIntent for withdrawal using CONFIGURED values
     * @param nullifierHash The nullifier hash from privacy pool withdrawal
     * @param refundCommitmentHash The commitment hash for refund recovery
     * @param escrowAmount The amount escrowed in OIF (includes solver fee)
     * @param netAmount The net amount user receives (after all fees)
     * @param destinationChainId The destination chain ID
     * @param encodedRecipient The encoded recipient (chainId + recipient address)
     * @param scope The privacy pool scope identifier
     * @return intent The created ShinobiIntent
     */
    function _createWithdrawalIntent(
        bytes32 nullifierHash,
        bytes32 refundCommitmentHash,
        uint256 escrowAmount,
        uint256 netAmount,
        uint256 destinationChainId,
        bytes32 encodedRecipient,
        uint256 scope
    ) internal view returns (ShinobiIntent memory intent) {
        // Get configured destination chain settings
        WithdrawalChainConfig storage destConfig = withdrawalChainConfig[destinationChainId];

        // Create refund calldata for returning to pool as commitment
        // Refund amount is the escrowAmount (what was escrowed, not what user would receive)
        bytes memory refundCalldata = abi.encode(
            address(this), // target: ShinobiCashEntrypoint
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(refundCommitmentHash), // refund commitment hash
                escrowAmount,                  // refund amount (escrowed amount)
                scope                          // privacy pool scope
            )
        );

        // Create inputs array - amount being ESCROWED (includes solver fee)
        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), escrowAmount]; // [token_address, amount] - 0 = native ETH

        // Create output using CONFIGURED values - amount user RECEIVES (net)
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destConfig.withdrawalFillOracle))),         // ✅ Configured oracle
            settler: bytes32(uint256(uint160(destConfig.withdrawalOutputSettler))),       // ✅ Configured settler
            chainId: destinationChainId,
            token: bytes32(0),                                                  // Native ETH
            amount: netAmount,                                                  // User receives this
            recipient: encodedRecipient,
            call: "",
            context: ""
        });

        // Create ShinobiIntent with CONFIGURED values
        intent = ShinobiIntent({
            user: address(this),                                               // ShinobiCashEntrypoint creates the order
            nonce: uint256(nullifierHash),                                     // Use nullifier hash as nonce for uniqueness
            originChainId: block.chainid,                                      // Current chain (Arbitrum)
            expires: uint32(block.timestamp) + destConfig.expiry,                  // ✅ Configured expiry
            fillDeadline: uint32(block.timestamp) + destConfig.fillDeadline,       // ✅ Configured fill deadline
            fillOracle: destConfig.fillOracle,                                            // ✅ Configured fill oracle
            inputs: inputs,                                                    // ✅ Auto-generated inputs
            outputs: outputs,                                                  // ✅ Auto-generated outputs with configured values
            intentOracle: address(0),                                          // No intent verification needed for withdrawals
            refundCalldata: refundCalldata                                     // Custom refund logic
        });
    }

    /**
     * @notice Calculate withdrawal fees
     * @dev Both relay and solver fees are calculated from the same base (withdrawnAmount)
     * @param _withdrawnAmount The total amount withdrawn from pool
     * @param _relayFeeBPS Relay fee in basis points (paid immediately to relayer)
     * @param _solverFeeBPS Solver fee in basis points (paid to solver when filling)
     * @return fees Struct containing relay and solver fees
     */
    function _calculateWithdrawalFees(
        uint256 _withdrawnAmount,
        uint256 _relayFeeBPS,
        uint256 _solverFeeBPS
    ) internal pure returns (WithdrawalFees memory fees) {
        // Calculate relay fee from withdrawn amount
        fees.relayFee = _withdrawnAmount - _deductFee(_withdrawnAmount, _relayFeeBPS);

        // Calculate solver fee from withdrawn amount (same base)
        fees.solverFee = _withdrawnAmount - _deductFee(_withdrawnAmount, _solverFeeBPS);
    }
}
