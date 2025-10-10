// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {ShinobiIntent} from "../types/ShinobiIntentType.sol";

/**
 * @title IShinobiInputSettler
 * @notice Interface for Shinobi Input Settler (origin chain - escrow side)
 * @dev Handles intent creation, escrow, and fund release after fill proof validation
 */
interface IShinobiInputSettler {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an intent is opened and funds escrowed
    /// @dev Matches OIF InputSettlerEscrow.Open event pattern
    event Open(bytes32 indexed orderId, ShinobiIntent intent);

    /// @notice Emitted when an intent is finalized and funds released to solver
    /// @dev Matches OIF InputSettlerBase.Finalised event pattern
    event Finalised(bytes32 indexed orderId, bytes32 solver, bytes32 destination);

    /// @notice Emitted when an intent is refunded
    /// @dev Matches OIF InputSettlerEscrow.Refunded event pattern
    event Refunded(bytes32 indexed orderId);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open an intent and escrow funds
     * @dev Validates intent structure and escrows msg.value
     * @param intent The shinobi intent to open
     */
    function open(ShinobiIntent calldata intent) external payable;

    /**
     * @notice Finalize an intent by validating fill proofs and releasing funds to solver
     * @dev Validates fill proofs via fillOracle before releasing escrowed funds
     * @param intent The original intent
     * @param fillProofs Array of fill proof data for oracle validation
     */
    function finalise(ShinobiIntent calldata intent, bytes[] calldata fillProofs) external;

    /**
     * @notice Refund an expired intent
     * @dev Can only be called after intent expiry
     * @dev If intent.refundCalldata is empty, transfers ETH to intent.user
     * @dev If intent.refundCalldata is present, executes custom refund logic
     * @param intent The original intent
     */
    function refund(ShinobiIntent calldata intent) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generate order identifier for an intent
     * @dev Compatible with OIF order identification
     * @param intent The intent data
     * @return The unique order identifier
     */
    function orderIdentifier(ShinobiIntent memory intent) external view returns (bytes32);
}
