// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @title IShinobiOutputSettler
 * @notice Interface for Shinobi Output Settler (destination chain - fill side)
 * @dev Handles intent validation and filling on destination chain
 */
interface IShinobiOutputSettler {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an output is successfully filled
    /// @dev Matches OIF OutputSettlerBase.OutputFilled event pattern
    event OutputFilled(
        bytes32 indexed orderId,
        bytes32 solver,
        uint32 timestamp,
        MandateOutput output,
        uint256 finalAmount
    );

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill an intent on destination chain
     * @dev Validates intent proof via intentOracle before accepting fill
     * @param intent The shinobi intent to fill
     */
    function fill(ShinobiIntent calldata intent) external payable;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the fill record for a specific intent
     * @param orderId The order identifier
     * @param outputHash The hash of the output
     * @return payloadHash The fill record hash if filled, zero otherwise
     */
    function getFillRecord(bytes32 orderId, bytes32 outputHash) external view returns (bytes32 payloadHash);
}
