// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {CrossChainProofLib} from "../libraries/CrossChainProofLib.sol";
  /**
   * @title IShinobiCashCrossChainHandler
   * @notice Interface for handling cross-chain privacy pool operations (deposits and withdrawals)
   * @dev Defines the contract capability to process cross-chain deposits and withdrawals
   */
  interface IShinobiCashCrossChainHandler {

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
    * @notice Enhanced relay data for cross-chain withdrawals
    * @dev Contains all information needed for cross-chain processing and refunds
    */
    struct CrossChainRelayData {
        address feeRecipient;          // Paymaster address (gets relay fees)
        uint256 relayFeeBPS;          // Fee in basis points (e.g., 1000 = 10%)
        uint256 solverFeeBPS;         // Solver fee in basis points
        bytes32 encodedDestination;   // chainId(32 bits) + recipient(160 bits) packed
    }

    /// @notice Struct to hold fee breakdown for withdrawals
    struct WithdrawalFees {
        uint256 relayFee;      // Fee paid to relayer immediately
        uint256 solverFee;     // Fee reserved for solver
    }


      /*//////////////////////////////////////////////////////////////
                                  EVENTS
      //////////////////////////////////////////////////////////////*/


      /**
       * @notice Emitted when a cross-chain intent fails and refund is processed
       * @param nullifier The nullifier from the original withdrawal
       * @param refundCommitmentHash The commitment created for refund recovery
       * @param refundAmount The amount available for refund
       */
      event CrossChainIntentFailed(
          bytes32 indexed nullifier,
          bytes32 indexed refundCommitmentHash,
          uint256 refundAmount
      );

      /*//////////////////////////////////////////////////////////////
                                  ERRORS
      //////////////////////////////////////////////////////////////*/

      error AmountMismatch(); 

      /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
      //////////////////////////////////////////////////////////////*/

      /**
       * @notice Process a cross-chain withdrawal request
       * @dev Main entry point for cross-chain withdrawals with enhanced proof validation
       * @dev Uses contract-configured values for oracles, settlers, and deadlines (NO user-provided params)
       * @param withdrawal The cross-chain withdrawal parameters
       * @param proof The enhanced ZK proof with refund commitment
       * @param scope The privacy pool scope identifier
       */
      function crosschainWithdrawal(
          IPrivacyPool.Withdrawal calldata withdrawal,
          CrossChainProofLib.CrossChainWithdrawProof calldata proof,
          uint256 scope
      ) external ;

      /**
       * @notice Process a cross-chain deposit with verified depositor address
       * @dev Called by ShinobiOutputSettler after intent proof validation
       * @dev CRITICAL: depositor parameter comes from VERIFIED intent.user via intent proof
       * @param depositor The verified depositor address from origin chain
       * @param amount The deposit amount
       * @param precommitment The precommitment for the deposit
       */
      function crosschainDeposit(
          address depositor,
          uint256 amount,
          uint256 precommitment
      ) external payable returns (uint256 _commitment);

  }