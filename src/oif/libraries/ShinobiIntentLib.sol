// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {ShinobiIntent} from "./ShinobiIntentType.sol";
import {StandardOrder} from "oif-contracts/input/types/StandardOrderType.sol";
import {MandateOutputType} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @title ShinobiIntentLib
 * @notice Library for ShinobiIntent utilities and conversions
 * @dev Provides helper functions for working with ShinobiIntent structs
 */
library ShinobiIntentLib {
    /**
     * @notice Convert ShinobiIntent to StandardOrder for OIF compatibility
     * @param intent The shinobi intent to convert
     * @return standardOrder The equivalent standard OIF order
     */
    function toStandardOrder(
        ShinobiIntent memory intent
    ) internal pure returns (StandardOrder memory standardOrder) {
        return StandardOrder({
            user: intent.user,
            nonce: intent.nonce,
            originChainId: intent.originChainId,
            expires: intent.expires,
            fillDeadline: intent.fillDeadline,
            inputOracle: intent.fillOracle,
            inputs: intent.inputs,
            outputs: intent.outputs
        });
    }

    /**
     * @notice Generate canonical order identifier from ShinobiIntent
     * @dev This is the SINGLE source of truth for intent identification
     * @dev Includes ALL ShinobiIntent fields and produces same hash on all chains
     * @param intent The intent data
     * @return orderId The unique order identifier
     */
    function orderIdentifier(
        ShinobiIntent memory intent
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                intent.user,
                intent.nonce,
                intent.originChainId,
                intent.expires,
                intent.fillDeadline,
                intent.fillOracle,
                keccak256(abi.encodePacked(intent.inputs)),
                keccak256(abi.encode(intent.outputs)),
                intent.intentOracle,
                keccak256(intent.refundCalldata)
            )
        );
    }

    /**
     * @notice Create custom refund calldata for a specific target and function call
     * @param target The target contract address
     * @param functionCalldata The function call data
     * @return The encoded refund calldata
     */
    function encodeRefundCalldata(
        address target,
        bytes memory functionCalldata
    ) internal pure returns (bytes memory) {
        return abi.encode(target, functionCalldata);
    }

    /**
     * @notice Validate intent structure
     * @param intent The intent to validate
     * @return isValid Whether the intent is structurally valid
     */
    function validateIntent(
        ShinobiIntent memory intent
    ) internal view returns (bool isValid) {
        if (intent.user == address(0)) return false;
        if (intent.inputs.length == 0) return false;
        if (intent.outputs.length == 0) return false;
        if (intent.fillDeadline <= block.timestamp) return false;
        if (intent.expires <= block.timestamp) return false;
        if (intent.expires <= intent.fillDeadline) return false;
        if (intent.intentOracle == address(0)) return false;
        if (intent.fillOracle == address(0)) return false;
        // Note: refundCalldata can be empty (for simple refunds)

        return true;
    }
}
