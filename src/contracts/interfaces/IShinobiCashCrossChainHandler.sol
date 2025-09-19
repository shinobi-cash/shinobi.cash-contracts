// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
  /**
   * @title ICrossChainHandler
   * @notice Interface for handling cross-chain privacy pool withdrawals
   * @dev Defines the contract capability to process withdrawals across different chains
   */
  interface IShinobiCashCrossChainHandler {
      
      /*//////////////////////////////////////////////////////////////
                                  STRUCTS
      //////////////////////////////////////////////////////////////*/
      
      /**
       * @notice Enhanced withdrawal parameters for cross-chain operations
       * @dev Extends standard withdrawal with cross-chain specific data
       */
      struct CrossChainWithdrawal {
          address processooor;            // Contract to process the withdrawal
          bytes data;                     // Encoded CrossChainRelayData
      }

      /**
       * @notice Enhanced ZK proof with refund commitment support
       * @dev Extends standard proof with additional public signal for refund commitment
       */
      struct CrossChainWithdrawProof {
          uint256[2] pA;                  // Groth16 proof component A
          uint256[2][2] pB;              // Groth16 proof component B
          uint256[2] pC;                  // Groth16 proof component C
          uint256[9] pubSignals;          // Extended public signals (9th = refundCommitmentHash)
      }

      /**
       * @notice Enhanced relay data for cross-chain withdrawals
       * @dev Contains all information needed for cross-chain processing and refunds
       */
      struct CrossChainRelayData {
          address feeRecipient;          // Paymaster address (gets relay fees)
          uint256 relayFeeBPS;          // Fee in basis points (e.g., 1000 = 10%)
          bytes32 encodedDestination;   // chainId(32 bits) + recipient(160 bits) packed
      }

      /**
       * @notice Cross-chain intent parameters needed for creating OIF StandardOrder
       * @dev User-provided parameters for OIF order creation
       */
      struct CrossChainIntentParams {
          uint32 fillDeadline;        // When the intent must be filled
          uint32 expires;             // When the intent expires  
          address inputOracle;        // Input oracle (usually address(0) for privacy pools)
          uint256[2][] inputs;        // Input tokens [address, amount]
          MandateOutput[] outputs;    // Output mandates for destination chain
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
                              CORE FUNCTIONS
      //////////////////////////////////////////////////////////////*/

      /**
       * @notice Process a cross-chain withdrawal request
       * @dev Main entry point for cross-chain withdrawals with enhanced proof validation
       * @param withdrawal The cross-chain withdrawal parameters
       * @param proof The enhanced ZK proof with refund commitment
       * @param scope The privacy pool scope identifier
       * @param intentParams User-provided intent parameters for validation
       */
      function processCrossChainWithdrawal(
          CrossChainWithdrawal calldata withdrawal,
          CrossChainWithdrawProof calldata proof,
          uint256 scope,
          CrossChainIntentParams calldata intentParams
      ) external;

      /**
       * @notice Check if a destination chain is supported
       * @dev Verifies that cross-chain withdrawals to the specified chain are enabled
       * @param chainId The chain ID to check
       * @return true if supported, false otherwise
       */
      function isChainSupported(uint256 chainId) external view returns (bool);

  }