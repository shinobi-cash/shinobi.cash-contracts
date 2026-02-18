// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IERC20} from "@oz/interfaces/IERC20.sol";

/**
 * @title ShinobiCashCrosschainState
 * @author Karandeep Singh
 * @notice State variables and events for cross-chain operations
 */
contract ShinobiCashCrosschainState {

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Withdraw2Nullifiers {
        uint256 nullifierHash0;
        uint256 nullifierHash1;
    }

    struct WithdrawalChainConfig {
        bool isConfigured;
        uint32 fillDeadline;
        uint32 expiry;
        address withdrawalOutputSettler;
        address withdrawalFillOracle;
        address fillOracle;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public withdrawalInputSettler;
    address public depositOutputSettler;
    uint256 internal _maxSolverFeeBPS;
    mapping(uint256 chainId => WithdrawalChainConfig config) internal _withdrawalChainConfig;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the maximum solver fee in basis points
    function maxSolverFeeBPS() external view virtual returns (uint256) {
        return _maxSolverFeeBPS;
    }

    /// @notice Get withdrawal chain configuration
    function withdrawalChainConfig(uint256 chainId) external view virtual returns (
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
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event WithdrawalInputSettlerUpdated(address indexed _previous, address indexed _new);
    event DepositOutputSettlerUpdated(address indexed _previous, address indexed _new);
    event MaxSolverFeeBPSUpdated(uint256 _previous, uint256 _new);

    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    );

    event CrosschainWithdrawalIntentRelayed(
        address indexed _relayer,
        bytes32 indexed _crosschainRecipient,
        IERC20 indexed _asset,
        uint256 _amount,
        uint256 _relayFee,
        uint256 _solverFee,
        bytes32 orderId
    );

    event CrosschainDeposited(
        address indexed _depositor,
        address indexed _pool,
        uint256 precommitment,
        uint256 _commitment,
        uint256 _amount
    );

    event Refunded(uint256 amount, uint256 indexed refundCommitmentHash, uint256 refundFee, address indexed feeRecipient);

    event Withdraw2Relayed(
        address indexed _relayer,
        address indexed _recipient,
        IERC20 indexed _asset,
        uint256 _amount,
        uint256 _feeAmount,
        Withdraw2Nullifiers _nullifiers
    );

    event CrosschainWithdraw2IntentRelayed(
        address indexed _relayer,
        bytes32 indexed _crosschainRecipient,
        IERC20 indexed _asset,
        uint256 _amount,
        uint256 _relayFee,
        uint256 _solverFee,
        bytes32 orderId,
        Withdraw2Nullifiers _nullifiers
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error WithdrawalInputSettlerNotSet();
    error DepositOutputSettlerNotSet();
    error DestinationChainNotConfigured();
    error FillOracleNotSet();
    error InvalidAddress();
    error OnlyWithdrawalInputSettler();
    error OnlyDepositOutputSettler();
    error DeadlineTooShort();
    error ExpiryBeforeFillDeadline();
    error InvalidChainId();
    error SolverFeeGreaterThanMax();
    error MaxSolverFeeBPSNotSet();
    error InvalidAsset();
    error RefundFeeTransferFailed();
}
