// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {Entrypoint} from "contracts/Entrypoint.sol";
import {CrosschainProofLib} from "./libraries/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "./libraries/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "./libraries/CrosschainWithdraw2ProofLib.sol";
import {ShinobiCashPool} from "./ShinobiCashPool.sol";
import {ShinobiCashPoolSimple} from "./implementations/ShinobiCashPoolSimple.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IShinobiCashCrosschainHandler} from "./interfaces/IShinobiCashCrosschainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ShinobiIntent} from "../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../oif/libraries/ShinobiIntentLib.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {ShinobiCashCrosschainState} from "./ShinobiCashCrosschainState.sol";

/**
 * @title ShinobiCashEntrypoint
 * @author Karandeep Singh
 * @notice Main orchestrator for cross-chain privacy pool operations
 * @dev Handles cross-chain withdrawals (1:1 and 2:1) and deposits via OIF intents
 */
contract ShinobiCashEntrypoint is Entrypoint, ShinobiCashCrosschainState, IShinobiCashCrosschainHandler {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct WithdrawalResult {
        bytes32 orderId;
        uint256 netAmount;
        uint256 relayFee;
        uint256 solverFee;
    }

    struct IntentCreationParams {
        bytes32 nullifierHash;
        bytes32 refundCommitmentHash;
        uint256 escrowAmount;
        uint256 netAmount;
        uint256 destinationChainId;
        bytes32 encodedRecipient;
        uint256 scope;
        address feeRecipient;
        uint256 refundFeeBPS;
    }

    struct CrosschainWithdraw2ProofData {
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        uint256 refundFeeBPS;
        bytes32 refundCommitmentHash;
        bytes32 nullifierHash0;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
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

    /// @notice Configure the withdrawal input settler address
    function setWithdrawalInputSettler(address _inputSettler) external onlyRole(_OWNER_ROLE) {
        if (_inputSettler == address(0)) revert InvalidAddress();
        address previous = withdrawalInputSettler;
        withdrawalInputSettler = _inputSettler;
        emit WithdrawalInputSettlerUpdated(previous, _inputSettler);
    }

    /// @notice Configure the deposit output settler address
    function setDepositOutputSettler(address _outputSettler) external onlyRole(_OWNER_ROLE) {
        if (_outputSettler == address(0)) revert InvalidAddress();
        address previous = depositOutputSettler;
        depositOutputSettler = _outputSettler;
        emit DepositOutputSettlerUpdated(previous, _outputSettler);
    }

    /// @notice Configure the maximum solver fee in basis points
    function setMaxSolverFeeBPS(uint256 __maxSolverFeeBPS) external onlyRole(_OWNER_ROLE) {
        if (__maxSolverFeeBPS > 10000) revert InvalidFeeBPS();
        uint256 previous = _maxSolverFeeBPS;
        _maxSolverFeeBPS = __maxSolverFeeBPS;
        emit MaxSolverFeeBPSUpdated(previous, __maxSolverFeeBPS);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IShinobiCashCrosschainHandler
    function maxSolverFeeBPS() external view override(ShinobiCashCrosschainState, IShinobiCashCrosschainHandler) returns (uint256) {
        return _maxSolverFeeBPS;
    }

    /// @inheritdoc IShinobiCashCrosschainHandler
    function withdrawalChainConfig(uint256 chainId) external view override(ShinobiCashCrosschainState, IShinobiCashCrosschainHandler) returns (
        bool isConfigured,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    ) {
        WithdrawalChainConfig storage config = _withdrawalChainConfig[chainId];
        return (
            config.isConfigured,
            config.fillDeadline,
            config.expiry,
            config.withdrawalOutputSettler,
            config.withdrawalFillOracle,
            config.fillOracle
        );
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure a destination chain for cross-chain withdrawals
    function setWithdrawalChainConfig(
        uint256 _chainId,
        address _outputSettler,
        address _outputOracle,
        address _fillOracle,
        uint32 _fillDeadline,
        uint32 _expiry
    ) external onlyRole(_OWNER_ROLE) {
        if (_chainId == 0) revert InvalidChainId();
        if (_outputSettler == address(0) || _outputOracle == address(0) || _fillOracle == address(0)) {
            revert InvalidAddress();
        }
        if (_fillDeadline < 300 || _expiry < 300) revert DeadlineTooShort();
        if (_expiry <= _fillDeadline) revert ExpiryBeforeFillDeadline();

        _withdrawalChainConfig[_chainId] = WithdrawalChainConfig({
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

    /// @notice Handle a cross-chain deposit with verified depositor address (native ETH)
    function crosschainDeposit(
        address _depositor,
        uint256 _amount,
        uint256 _precommitment
    ) external payable override nonReentrant onlyDepositOutputSettler returns (uint256 _commitment) {
        if (msg.value != _amount) revert AmountMismatch();
        _commitment = _handleCrosschainDeposit(IERC20(Constants.NATIVE_ASSET), _depositor, msg.value, _precommitment);
    }

    /// @notice Handle a cross-chain deposit with verified depositor address (ERC20)
    /// @dev Tokens must be transferred to this contract before calling
    function crosschainDepositERC20(
        IERC20 _asset,
        address _depositor,
        uint256 _amount,
        uint256 _precommitment
    ) external nonReentrant onlyDepositOutputSettler returns (uint256 _commitment) {
        if (address(_asset) == Constants.NATIVE_ASSET) revert InvalidAsset();
        _commitment = _handleCrosschainDeposit(_asset, _depositor, _amount, _precommitment);
    }


    /// @inheritdoc IShinobiCashCrosschainHandler
    function crosschainWithdrawal(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof calldata _proof,
        uint256 _scope
    ) external override nonReentrant {
        if (withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (_maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        IERC20 _asset = IERC20(_shinobiPool.ASSET());
        uint256 _balanceBefore = _assetBalance(_asset);

        CrosschainRelayData memory _data = abi.decode(_withdrawal.data, (CrosschainRelayData));

        if (!_withdrawalChainConfig[uint256(_data.encodedDestination) >> 224].isConfigured) {
            revert DestinationChainNotConfigured();
        }

        // Read fees from proof (circuit is single source of truth)
        if (_proof.relayFeeBPS() > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (_data.solverFeeBPS > _maxSolverFeeBPS) revert SolverFeeGreaterThanMax();

        _shinobiPool.crosschainWithdraw(_withdrawal, _proof);

        WithdrawalResult memory result = _openWithdrawalIntent(
            _asset,
            _proof.withdrawnValue(),
            _proof.relayFeeBPS(),
            _proof.refundFeeBPS(),
            _data,
            _scope,
            bytes32(_proof.existingNullifierHash()),
            bytes32(_proof.refundCommitmentHash())
        );

        if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();

        emit CrosschainWithdrawalIntentRelayed(
            msg.sender,
            _data.encodedDestination,
            _asset,
            result.netAmount,
            result.relayFee,
            result.solverFee,
            result.orderId
        );
    }


    /**
     * @notice Process a same-chain Withdraw2 (2 inputs -> 1 output + withdrawal)
     * @param _withdrawal The withdrawal parameters
     * @param _proof The Withdraw2 9-signal proof
     * @param _scope The privacy pool scope identifier
     */
    function relay2(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof calldata _proof,
        uint256 _scope
    ) external nonReentrant {
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        Withdraw2Nullifiers memory nullifiers = Withdraw2Nullifiers(
            _proof.nullifierHash0(),
            _proof.nullifierHash1()
        );

        _executeRelay2(_withdrawal, _proof, _scope, nullifiers);
    }

    function _executeRelay2(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        Withdraw2ProofLib.Withdraw2Proof calldata _proof,
        uint256 _scope,
        Withdraw2Nullifiers memory _nullifiers
    ) internal {
        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        IERC20 _asset = IERC20(_shinobiPool.ASSET());
        uint256 _balanceBefore = _assetBalance(_asset);

        _shinobiPool.withdraw2(_withdrawal, _proof);

        RelayData memory _data = abi.decode(_withdrawal.data, (RelayData));
        if (_data.relayFeeBPS > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        uint256 _withdrawnAmount = _proof.withdrawnValue();
        uint256 _amountAfterFees = _deductFee(_withdrawnAmount, _data.relayFeeBPS);
        uint256 _feeAmount = _withdrawnAmount - _amountAfterFees;

        _transfer(_asset, _data.recipient, _amountAfterFees);
        _transfer(_asset, _data.feeRecipient, _feeAmount);

        if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();

        emit Withdraw2Relayed(
            msg.sender,
            _data.recipient,
            _asset,
            _withdrawnAmount,
            _feeAmount,
            _nullifiers
        );
    }

    /**
     * @notice Process a cross-chain Withdraw2 (2 inputs -> 1 output + OIF intent)
     * @param _withdrawal The withdrawal parameters
     * @param _proof The Withdraw2 10-signal proof
     * @param _scope The privacy pool scope identifier
     */
    function crossChainWithdrawal2(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata _proof,
        uint256 _scope
    ) external nonReentrant {
        if (withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (_maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        Withdraw2Nullifiers memory nullifiers = Withdraw2Nullifiers(
            _proof.nullifierHash0(),
            _proof.nullifierHash1()
        );

        _executeCrosschainWithdraw2(_withdrawal, _proof, _scope, nullifiers);
    }

    function _executeCrosschainWithdraw2(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata _proof,
        uint256 _scope,
        Withdraw2Nullifiers memory _nullifiers
    ) internal {
        // Extract all proof values upfront to avoid stack issues later
        CrosschainWithdraw2ProofData memory proofData = CrosschainWithdraw2ProofData({
            withdrawnValue: _proof.withdrawnValue(),
            relayFeeBPS: _proof.relayFeeBPS(),
            refundFeeBPS: _proof.refundFeeBPS(),
            refundCommitmentHash: bytes32(_proof.refundCommitmentHash()),
            nullifierHash0: bytes32(_nullifiers.nullifierHash0)
        });

        IERC20 _asset;
        bytes32 _encodedDestination;
        WithdrawalResult memory result;

        // Scoped block for pool and intent operations
        {
            CrosschainRelayData memory _data = abi.decode(_withdrawal.data, (CrosschainRelayData));
            _encodedDestination = _data.encodedDestination;

            if (!_withdrawalChainConfig[uint256(_encodedDestination) >> 224].isConfigured) {
                revert DestinationChainNotConfigured();
            }

            uint256 _balanceBefore;

            {
                ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
                if (address(_shinobiPool) == address(0)) revert PoolNotFound();

                _asset = IERC20(_shinobiPool.ASSET());
                _balanceBefore = _assetBalance(_asset);

                if (proofData.relayFeeBPS > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
                if (_data.solverFeeBPS > _maxSolverFeeBPS) revert SolverFeeGreaterThanMax();

                _shinobiPool.crossChainWithdraw2(_withdrawal, _proof);
            }

            result = _openWithdrawalIntent(
                _asset,
                proofData.withdrawnValue,
                proofData.relayFeeBPS,
                proofData.refundFeeBPS,
                _data,
                _scope,
                proofData.nullifierHash0,
                proofData.refundCommitmentHash
            );

            if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();
        }

        emit CrosschainWithdraw2IntentRelayed(
            msg.sender,
            _encodedDestination,
            _asset,
            result.netAmount,
            result.relayFee,
            result.solverFee,
            result.orderId,
            _nullifiers
        );
    }

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev The refundCommitmentHash from circuit is correctly computed with netRefundAmount
     * @param _refundCommitmentHash The commitment hash for refund (from circuit, tied to netRefundAmount)
     * @param _feeRecipient The address to receive the refund fee
     * @param _refundFeeBPS The refund fee in basis points (from circuit)
     * @param _scope The privacy pool scope identifier
     */
    function handleRefund(
        uint256 _refundCommitmentHash,
        address _feeRecipient,
        uint256 _refundFeeBPS,
        uint256 _scope
    ) external payable onlyWithdrawalInputSettler {
        uint256 escrowAmount = msg.value;

        // Calculate refund fee
        uint256 refundFee = escrowAmount - _deductFee(escrowAmount, _refundFeeBPS);
        uint256 netRefundAmount = escrowAmount - refundFee;

        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        // Pay refund fee to recipient (paymaster/relayer)
        if (refundFee > 0) {
            (bool success,) = _feeRecipient.call{value: refundFee}("");
            if (!success) revert RefundFeeTransferFailed();
        }

        // Insert circuit's refundCommitmentHash (correctly tied to netRefundAmount)
        _shinobiPool.handleRefund{value: netRefundAmount}(_refundCommitmentHash, netRefundAmount);

        emit Refunded(netRefundAmount, _refundCommitmentHash, refundFee, _feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _openWithdrawalIntent(
        IERC20 _asset,
        uint256 _withdrawnAmount,
        uint256 _relayFeeBPS,
        uint256 _refundFeeBPS,
        CrosschainRelayData memory _data,
        uint256 _scope,
        bytes32 _nullifierHash,
        bytes32 _refundCommitmentHash
    ) internal returns (WithdrawalResult memory result) {
        WithdrawalFees memory fees = _calculateWithdrawalFees(_withdrawnAmount, _relayFeeBPS, _data.solverFeeBPS);

        IntentCreationParams memory params = IntentCreationParams({
            nullifierHash: _nullifierHash,
            refundCommitmentHash: _refundCommitmentHash,
            escrowAmount: _withdrawnAmount - fees.relayFee,
            netAmount: _withdrawnAmount - fees.relayFee - fees.solverFee,
            destinationChainId: uint256(_data.encodedDestination) >> 224,
            encodedRecipient: _data.encodedDestination,
            scope: _scope,
            feeRecipient: _data.feeRecipient,
            refundFeeBPS: _refundFeeBPS
        });

        ShinobiIntent memory intent = _createWithdrawalIntent(params);

        _transfer(_asset, _data.feeRecipient, fees.relayFee);
        IShinobiInputSettler(withdrawalInputSettler).open{value: params.escrowAmount}(intent);

        result.orderId = intent.orderIdentifier();
        result.netAmount = params.netAmount;
        result.relayFee = fees.relayFee;
        result.solverFee = fees.solverFee;
    }

    function _handleCrosschainDeposit(
        IERC20 _asset,
        address _depositor,
        uint256 _amount,
        uint256 _precommitment
    ) internal returns (uint256 _commitment) {
        AssetConfig memory config = assetConfig[_asset];
        IPrivacyPool pool = config.pool;
        if (address(pool) == address(0)) revert PoolNotFound();

        if (usedPrecommitments[_precommitment]) revert PrecommitmentAlreadyUsed();
        usedPrecommitments[_precommitment] = true;

        if (_amount < config.minimumDepositAmount) revert MinimumDepositAmount();

        uint256 _amountAfterFees = _deductFee(_amount, config.vettingFeeBPS);
        uint256 _nativeAssetValue = address(_asset) == Constants.NATIVE_ASSET ? _amountAfterFees : 0;
        _commitment = pool.deposit{value: _nativeAssetValue}(_depositor, _amountAfterFees, _precommitment);

        emit CrosschainDeposited(_depositor, address(pool), _precommitment, _commitment, _amountAfterFees);
    }


    function _createWithdrawalIntent(
        IntentCreationParams memory p
    ) internal view returns (ShinobiIntent memory intent) {
        WithdrawalChainConfig storage destConfig = _withdrawalChainConfig[p.destinationChainId];

        // refundCalldata includes feeRecipient and refundFeeBPS for fee payment on refund
        bytes memory refundCalldata = abi.encode(
            address(this),
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(p.refundCommitmentHash),
                p.feeRecipient,
                p.refundFeeBPS,
                p.scope
            )
        );

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), p.escrowAmount];

        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destConfig.withdrawalFillOracle))),
            settler: bytes32(uint256(uint160(destConfig.withdrawalOutputSettler))),
            chainId: p.destinationChainId,
            token: bytes32(0),
            amount: p.netAmount,
            recipient: bytes32(uint256(uint160(uint256(p.encodedRecipient)))),
            call: "",
            context: ""
        });

        intent = ShinobiIntent({
            user: address(this),
            nonce: uint256(p.nullifierHash),
            originChainId: block.chainid,
            expires: uint32(block.timestamp) + destConfig.expiry,
            fillDeadline: uint32(block.timestamp) + destConfig.fillDeadline,
            fillOracle: destConfig.fillOracle,
            inputs: inputs,
            outputs: outputs,
            intentOracle: address(0),
            refundCalldata: refundCalldata
        });
    }

    function _calculateWithdrawalFees(
        uint256 _withdrawnAmount,
        uint256 _relayFeeBPS,
        uint256 _solverFeeBPS
    ) internal pure returns (WithdrawalFees memory fees) {
        fees.relayFee = _withdrawnAmount - _deductFee(_withdrawnAmount, _relayFeeBPS);
        fees.solverFee = _withdrawnAmount - _deductFee(_withdrawnAmount, _solverFeeBPS);
    }
}
