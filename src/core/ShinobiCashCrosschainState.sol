// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IERC20} from "@oz/interfaces/IERC20.sol";

contract ShinobiCashCrosschainState {


    /// @notice Configuration for destination chains
    struct WithdrawalChainConfig {
        bool isConfigured;           // Whether this destination is configured
        uint32 fillDeadline; // Default fill deadline for withdrawal intents (relative to block.timestamp)
        uint32 expiry;      // Default expiry for withdrawal intents (relative to block.timestamp)
        address withdrawalOutputSettler;       // ShinobiWithdrawalOutputSettler address on destination
        address withdrawalFillOracle;  // Output Oracle address on destination chain
        address fillOracle;       // Fill oracle address for validating fills (destination → origin)
    }
    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the ShinobiCashInputSettler for cross-chain withdrawals
    address public withdrawalInputSettler;

    /// @notice Address of the ShinobiCashDepositOutputSettler for cross-chain deposits
    address public depositOutputSettler;

    /// @notice Mapping of destination chain ID to its configuration
    mapping(uint256 chainId => WithdrawalChainConfig config) public withdrawalChainConfig;

     /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when the ShinobiInputSettler address is updated
    /// @param _previous The previous ShinobiInputSettler address
    /// @param _new The new ShinobiInputSettler address
    event WithdrawalInputSettlerUpdated(address indexed _previous, address indexed _new);

    /// @notice Emitted when the ShinobiOutputSettler address is updated
    /// @param _previous The previous ShinobiOutputSettler address
    /// @param _new The new ShinobiOutputSettler address
    event DepositOutputSettlerUpdated(address indexed _previous, address indexed _new);

    /// @notice Emitted when a destination chain configuration is updated
    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline, 
        uint32 expiry,     
        address withdrawalOutputSettler,      
        address withdrawalFillOracle,  
        address fillOracle  
    );

    /// @notice Emitted when a user initiates a cross-chain withdrawal
    /// @param _relayer The address initiating the withdrawal
    /// @param _crosschainRecipient The final recipient encode with destination chain
    /// @param _asset The asset being withdrawn
    /// @param _amount The net amount after fees
    /// @param _feeAmount The fee amount deducted
    /// @param orderId The unique order identifier for tracking (links to InputSettler.Open event)
    event CrossChainWithdrawalIntentRelayed(
        address indexed _relayer,
        bytes32 indexed _crosschainRecipient, 
        IERC20 indexed _asset,
        uint256 _amount,
        uint256 _feeAmount,
        bytes32 orderId
    );

    /**
    * @notice Emitted when pushing a new root to the association root set
    * @param _depositor The address of the depositor
    * @param _pool The Shinobi Cash Pool contract
    * @param precommitment The precommitment for the deposit
    * @param _commitment The commitment hash for the deposit
    * @param _amount The amount of asset deposited
    */
    event CrosschainDeposited(address indexed _depositor, address indexed _pool, uint256 precommitment, uint256 _commitment, uint256 _amount);

    /// @notice Emitted when a cross-chain refund is processed
    event Refunded(
        uint256 amount,
        uint256 indexed refundCommitmentHash
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when withdrawal input settler address is not set
    error WithdrawalInputSettlerNotSet();

    /// @notice Thrown when deposit output settler address is not set
    error DepositOutputSettlerNotSet();

    /// @notice Thrown when destination chain is not configured for withdrawals
    error DestinationChainNotConfigured();

    /// @notice Thrown when fill oracle is not set
    error FillOracleNotSet();

    /// @notice Thrown when setter is called with zero address
    error InvalidAddress();

    /// @notice Thrown when caller is not the configured withdrawal input settler
    error OnlyWithdrawalInputSettler();

    /// @notice Thrown when caller is not the configured deposit output settler
    error OnlyDepositOutputSettler();

    /// @notice Thrown when deadline is less than minimum (5 minutes)
    error DeadlineTooShort();

    /// @notice Thrown when expiry is not greater than fillDeadline
    error ExpiryBeforeFillDeadline();

}