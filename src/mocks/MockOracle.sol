// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";

/**
 * @title MockOracle
 * @notice Mock oracle that always returns true for testing purposes
 * @dev WARNING: NEVER USE IN PRODUCTION - This bypasses all validation
 */
contract MockOracle is IInputOracle {
    /**
     * @notice Mock implementation that always returns true
     * @dev This allows any intent/fill to be considered proven
     * @return Always returns true
     */
    function isProven(
        uint256, // originChainId
        bytes32, // inputOracle
        bytes32, // outputOracle
        bytes32  // orderId
    ) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Mock implementation that always succeeds
     * @dev This allows batch validation to pass without checking
     */
    function efficientRequireProven(bytes calldata) external pure override {
        // Always succeeds - no validation
        return;
    }
}
