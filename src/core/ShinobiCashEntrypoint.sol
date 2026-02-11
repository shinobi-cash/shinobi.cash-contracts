// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {Entrypoint} from "contracts/Entrypoint.sol";
import {CrossChainProofLib} from "./libraries/CrossChainProofLib.sol";
import {Withdraw2ProofLib} from "./libraries/Withdraw2ProofLib.sol";
import {CrossChainWithdraw2ProofLib} from "./libraries/CrossChainWithdraw2ProofLib.sol";
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
 * @author Karandeep Singh
 * @notice Main orchestrator for cross-chain privacy pool operations
 * @dev Handles cross-chain withdrawals (1:1 and 2:1) and deposits via OIF intents
 */
contract ShinobiCashEntrypoint is Entrypoint, ShinobiCashCrosschainState, IShinobiCashCrossChainHandler {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using Withdraw2ProofLib for Withdraw2ProofLib.Withdraw2Proof;
    using CrossChainWithdraw2ProofLib for CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof;
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
    function setMaxSolverFeeBPS(uint256 _maxSolverFeeBPS) external onlyRole(_OWNER_ROLE) {
        if (_maxSolverFeeBPS > 10000) revert InvalidFeeBPS();
        uint256 previous = maxSolverFeeBPS;
        maxSolverFeeBPS = _maxSolverFeeBPS;
        emit MaxSolverFeeBPSUpdated(previous, _maxSolverFeeBPS);
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
    function crosschainDeposit(
        address _depositor,
        uint256 _amount,
        uint256 _precommitment
    ) external payable override nonReentrant onlyDepositOutputSettler returns (uint256 _commitment) {
        if (msg.value != _amount) revert AmountMismatch();
        _commitment = _handleCrosschainDeposit(IERC20(Constants.NATIVE_ASSET), _depositor, msg.value, _precommitment);
    }


    /// @inheritdoc IShinobiCashCrossChainHandler
    function crosschainWithdrawal(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof calldata _proof,
        uint256 _scope
    ) external override nonReentrant {
        if (withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        IERC20 _asset = IERC20(_shinobiPool.ASSET());
        uint256 _balanceBefore = _assetBalance(_asset);

        CrossChainRelayData memory _data = abi.decode(_withdrawal.data, (CrossChainRelayData));

        if (!withdrawalChainConfig[uint256(_data.encodedDestination) >> 224].isConfigured) {
            revert DestinationChainNotConfigured();
        }
        if (_data.relayFeeBPS > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (_data.solverFeeBPS > maxSolverFeeBPS) revert SolverFeeGreaterThanMax();

        _shinobiPool.crosschainWithdraw(_withdrawal, _proof);

        WithdrawalResult memory result = _openWithdrawalIntent(
            _asset,
            _proof.withdrawnValue(),
            _data,
            _scope,
            bytes32(_proof.existingNullifierHash()),
            bytes32(_proof.refundCommitmentHash())
        );

        if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();

        emit CrossChainWithdrawalIntentRelayed(
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
        CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof calldata _proof,
        uint256 _scope
    ) external nonReentrant {
        if (withdrawalInputSettler == address(0)) revert WithdrawalInputSettlerNotSet();
        if (maxSolverFeeBPS == 0) revert MaxSolverFeeBPSNotSet();
        if (_proof.withdrawnValue() == 0) revert InvalidWithdrawalAmount();
        if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

        Withdraw2Nullifiers memory nullifiers = Withdraw2Nullifiers(
            _proof.nullifierHash0(),
            _proof.nullifierHash1()
        );

        _executeCrossChainWithdraw2(_withdrawal, _proof, _scope, nullifiers);
    }

    function _executeCrossChainWithdraw2(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        CrossChainWithdraw2ProofLib.CrossChainWithdraw2Proof calldata _proof,
        uint256 _scope,
        Withdraw2Nullifiers memory _nullifiers
    ) internal {
        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

        IERC20 _asset = IERC20(_shinobiPool.ASSET());
        uint256 _balanceBefore = _assetBalance(_asset);

        CrossChainRelayData memory _data = abi.decode(_withdrawal.data, (CrossChainRelayData));

        if (!withdrawalChainConfig[uint256(_data.encodedDestination) >> 224].isConfigured) {
            revert DestinationChainNotConfigured();
        }
        if (_data.relayFeeBPS > assetConfig[_asset].maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
        if (_data.solverFeeBPS > maxSolverFeeBPS) revert SolverFeeGreaterThanMax();

        _shinobiPool.crossChainWithdraw2(_withdrawal, _proof);

        WithdrawalResult memory result = _openWithdrawalIntent(
            _asset,
            _proof.withdrawnValue(),
            _data,
            _scope,
            bytes32(_nullifiers.nullifierHash0),
            bytes32(_proof.refundCommitmentHash())
        );

        if (_balanceBefore > _assetBalance(_asset)) revert InvalidPoolState();

        emit CrossChainWithdraw2IntentRelayed(
            msg.sender,
            _data.encodedDestination,
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
     * @param _refundCommitmentHash The commitment hash for refund
     * @param _amount The amount being refunded
     * @param _scope The privacy pool scope identifier
     */
    function handleRefund(
        uint256 _refundCommitmentHash,
        uint256 _amount,
        uint256 _scope
    ) external payable onlyWithdrawalInputSettler {
        if (msg.value != _amount) revert AmountMismatch();

        ShinobiCashPool _shinobiPool = ShinobiCashPool(address(scopeToPool[_scope]));
        if (address(_shinobiPool) == address(0)) revert PoolNotFound();

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

        uint256 _escrowAmount = _withdrawnAmount - fees.relayFee;
        uint256 _netAmount = _withdrawnAmount - fees.relayFee - fees.solverFee;

        ShinobiIntent memory intent = _createWithdrawalIntent(
            _nullifierHash,
            _refundCommitmentHash,
            _escrowAmount,
            _netAmount,
            uint256(_data.encodedDestination) >> 224,
            _data.encodedDestination,
            _scope
        );

        _transfer(_asset, _data.feeRecipient, fees.relayFee);
        IShinobiInputSettler(withdrawalInputSettler).open{value: _escrowAmount}(intent);

        result.orderId = intent.orderIdentifier();
        result.netAmount = _netAmount;
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
        _commitment = pool.deposit{value: _nativeAssetValue}(_depositor, _nativeAssetValue, _precommitment);

        emit CrosschainDeposited(_depositor, address(pool), _precommitment, _commitment, _amountAfterFees);
    }


    function _createWithdrawalIntent(
        bytes32 nullifierHash,
        bytes32 refundCommitmentHash,
        uint256 escrowAmount,
        uint256 netAmount,
        uint256 destinationChainId,
        bytes32 encodedRecipient,
        uint256 scope
    ) internal view returns (ShinobiIntent memory intent) {
        WithdrawalChainConfig storage destConfig = withdrawalChainConfig[destinationChainId];

        bytes memory refundCalldata = abi.encode(
            address(this),
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(refundCommitmentHash),
                escrowAmount,
                scope
            )
        );

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), escrowAmount];

        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = MandateOutput({
            oracle: bytes32(uint256(uint160(destConfig.withdrawalFillOracle))),
            settler: bytes32(uint256(uint160(destConfig.withdrawalOutputSettler))),
            chainId: destinationChainId,
            token: bytes32(0),
            amount: netAmount,
            recipient: bytes32(uint256(uint160(uint256(encodedRecipient)))),
            call: "",
            context: ""
        });

        intent = ShinobiIntent({
            user: address(this),
            nonce: uint256(nullifierHash),
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
