// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";

/**
 * @title IHyperlaneOracle
 * @notice Interface for HyperlaneOracle used for cross-chain intent proof relay
 * @dev Extends IInputOracle with Hyperlane-specific submit and quote functions
 */
interface IHyperlaneOracle is IInputOracle {
    /**
     * @notice Submit payloads to be relayed via Hyperlane to destination chain
     * @param destinationDomain The Hyperlane domain ID of the destination chain
     * @param recipientOracle The address of the oracle on the destination domain
     * @param gasLimit Gas limit for the message execution on destination
     * @param customMetadata Additional metadata for the hook
     * @param source Application that created the payloads
     * @param payloads List of payloads to broadcast
     */
    function submit(
        uint32 destinationDomain,
        address recipientOracle,
        uint256 gasLimit,
        bytes calldata customMetadata,
        address source,
        bytes[] calldata payloads
    ) external payable;

    /**
     * @notice Quote the gas payment required to dispatch a message
     * @param destinationDomain The Hyperlane domain ID of the destination chain
     * @param recipientOracle The address of the oracle on the destination domain
     * @param gasLimit Gas limit for the message execution on destination
     * @param customMetadata Additional metadata for the hook
     * @param source Application that created the payloads
     * @param payloads List of payloads to broadcast
     * @return gasPayment The required payment for cross-chain delivery
     */
    function quoteGasPayment(
        uint32 destinationDomain,
        address recipientOracle,
        uint256 gasLimit,
        bytes calldata customMetadata,
        address source,
        bytes[] calldata payloads
    ) external view returns (uint256 gasPayment);
}
