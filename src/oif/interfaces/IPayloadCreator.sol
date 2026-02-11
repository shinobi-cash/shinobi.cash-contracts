// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/**
 * @title IPayloadCreator
 * @notice Interface for contracts that create payloads for cross-chain oracle relay
 * @dev Implemented by applications that submit payloads via HyperlaneOracle
 */
interface IPayloadCreator {
    /**
     * @notice Validate that the provided payloads were created by this contract
     * @dev Called by HyperlaneOracle before relaying payloads
     * @param payloads Array of encoded payloads to validate
     * @return valid True if all payloads are valid, false otherwise
     */
    function arePayloadsValid(bytes[] calldata payloads) external view returns (bool valid);
}
