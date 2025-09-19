// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {StandardOrder} from "oif-contracts/input/types/StandardOrderType.sol";
import {IExtendedOrder} from "../interfaces/IExtendedOrder.sol";

/**
 * @title ExtendedOrderLib
 * @notice Library for extended OIF order utilities and conversions
 * @dev Provides helper functions for working with ExtendedOrder structs
 */
library ExtendedOrderLib {

    /**
     * @notice Convert ExtendedOrder to StandardOrder for OIF compatibility
     * @param extendedOrder The extended order to convert
     * @return standardOrder The equivalent standard order
     */
    function toStandardOrder(
        IExtendedOrder.ExtendedOrder memory extendedOrder
    ) internal pure returns (StandardOrder memory standardOrder) {
        return StandardOrder({
            user: extendedOrder.user,
            nonce: extendedOrder.nonce,
            originChainId: extendedOrder.originChainId,
            expires: extendedOrder.expires,
            fillDeadline: extendedOrder.fillDeadline,
            inputOracle: extendedOrder.inputOracle,
            inputs: extendedOrder.inputs,
            outputs: extendedOrder.outputs
        });
    }

    /**
     * @notice Generate order identifier for extended order
     * @param extendedOrder The extended order data
     * @param settler The settler contract address
     * @return The unique order identifier
     */
    function orderIdentifier(
        IExtendedOrder.ExtendedOrder memory extendedOrder,
        address settler
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                extendedOrder.originChainId,
                settler,
                extendedOrder.user,
                extendedOrder.nonce,
                extendedOrder.expires,
                extendedOrder.fillDeadline,
                extendedOrder.inputOracle,
                keccak256(abi.encodePacked(extendedOrder.inputs)),
                abi.encode(extendedOrder.outputs),
                extendedOrder.refundCalldataHash
            )
        );
    }

    /**
     * @notice Create refund calldata for a specific target and function call
     * @param target The target contract address
     * @param functionCalldata The function call data
     * @return The encoded refund calldata
     */
    function createRefundCalldata(
        address target,
        bytes memory functionCalldata
    ) internal pure returns (bytes memory) {
        return abi.encode(target, functionCalldata);
    }

    /**
     * @notice Create refund calldata hash
     * @param target The target contract address
     * @param functionCalldata The function call data
     * @return The hash of the refund calldata
     */
    function createRefundCalldataHash(
        address target,
        bytes memory functionCalldata
    ) internal pure returns (bytes32) {
        return keccak256(createRefundCalldata(target, functionCalldata));
    }

    /**
     * @notice Validate extended order structure
     * @param extendedOrder The order to validate
     * @return isValid Whether the order is structurally valid
     */
    function validateExtendedOrder(
        IExtendedOrder.ExtendedOrder memory extendedOrder
    ) internal view returns (bool isValid) {
        if (extendedOrder.user == address(0)) return false;
        if (extendedOrder.inputs.length == 0) return false;
        if (extendedOrder.outputs.length == 0) return false;
        if (extendedOrder.fillDeadline <= block.timestamp) return false;
        if (extendedOrder.expires <= block.timestamp) return false;
        if (extendedOrder.expires <= extendedOrder.fillDeadline) return false;
        if (extendedOrder.refundCalldataHash == bytes32(0)) return false;
        
        return true;
    }
}