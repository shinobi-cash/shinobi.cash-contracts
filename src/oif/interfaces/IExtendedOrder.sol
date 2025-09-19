// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @title IExtendedOrder
 * @notice Interface for extended OIF orders with custom refund calldata capability
 * @dev Extends standard OIF orders to support arbitrary refund logic for any protocol
 */
interface IExtendedOrder {

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Extended StandardOrder with refund calldata capability
    struct ExtendedOrder {
        address user;
        uint256 nonce;
        uint256 originChainId;
        uint32 expires;
        uint32 fillDeadline;
        address inputOracle;
        uint256[2][] inputs;
        MandateOutput[] outputs;
        bytes32 refundCalldataHash;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an extended order is opened
    event ExtendedOpen(bytes32 indexed orderId, bytes32 refundCalldataHash);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRefundCalldata();
    error RefundExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open an extended order with custom refund capability
     * @param extendedOrder The extended order with refund calldata hash
     */
    function openExtended(ExtendedOrder calldata extendedOrder) external payable;

    /**
     * @notice Refund an expired order with custom calldata execution
     * @param order The original standard order data
     * @param refundCalldata The refund calldata to execute (must match committed hash)
     */
    function refundWithCalldata(
        ExtendedOrder calldata order,
        bytes calldata refundCalldata
    ) external;

    /**
     * @notice Get the refund calldata hash for an order
     * @param orderId The order identifier
     * @return The committed refund calldata hash
     */
    function getRefundCalldataHash(bytes32 orderId) external view returns (bytes32);

    /**
     * @notice Generate order identifier for extended order
     * @param order The extended order data
     * @return The unique order identifier
     */
    function extendedOrderIdentifier(ExtendedOrder memory order) external view returns (bytes32);
}