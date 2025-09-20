// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {InputSettlerEscrow} from "oif-contracts/input/escrow/InputSettlerEscrow.sol";
import {StandardOrder, StandardOrderType} from "oif-contracts/input/types/StandardOrderType.sol";
import {LibAddress} from "oif-contracts/libs/LibAddress.sol";
import {IExtendedOrder} from "../interfaces/IExtendedOrder.sol";
import {ExtendedOrderLib} from "../lib/ExtendedOrderLib.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ExtendedInputSettler  
 * @notice Extended OIF InputSettlerEscrow with custom refund calldata execution
 * @dev Inherits all OIF functionality and adds arbitrary refund logic for any protocol
 */
contract ExtendedInputSettler is InputSettlerEscrow, IExtendedOrder {
    using SafeERC20 for IERC20;
    using ExtendedOrderLib for IExtendedOrder.ExtendedOrder;
    using LibAddress for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping from order ID to refund calldata hash
    mapping(bytes32 => bytes32) public orderRefundCalldata;

    /*//////////////////////////////////////////////////////////////
                            EXTENDED FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    /**
     * @notice Refund an expired order with custom calldata execution
     * @param order The original extended order data
     * @param refundCalldata The refund calldata to execute (must match committed hash)
     */
    function refundWithCalldata(
        ExtendedOrder calldata order,
        bytes calldata refundCalldata
    ) external override {
        // Validate order has expired (following OIF pattern)
        _validateInputChain(order.originChainId);
        _validateTimestampHasPassed(order.expires);

        StandardOrder memory standardOrder = order.toStandardOrder();
        bytes32 orderId = this.orderIdentifier(standardOrder);
        
        // Check order is in deposited state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Validate refund calldata matches committed hash
        bytes32 committedHash = orderRefundCalldata[orderId];
        if (committedHash == bytes32(0)) {
            revert("No refund calldata hash found - order was not opened with custom refund");
        }

        if (keccak256(refundCalldata) != committedHash) {
            revert InvalidRefundCalldata();
        }

        // Update status to refunded
        orderStatus[orderId] = OrderStatus.Refunded;

        // Decode and execute custom refund logic
        (address target, bytes memory functionCalldata) = abi.decode(
            refundCalldata, 
            (address, bytes)
        );

        _executeCustomRefund(order.inputs, target, functionCalldata);

        emit Refunded(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override openExtended to handle native ETH properly
     * @dev This version bypasses the parent's open() call for native ETH
     * @param extendedOrder The extended order with refund calldata hash
     */
    function openExtended(ExtendedOrder calldata extendedOrder) external payable override {
        // Convert ExtendedOrder to StandardOrder for OIF compatibility
        StandardOrder memory standardOrder = extendedOrder.toStandardOrder();

        // Validate the order structure
        _validateInputChain(standardOrder.originChainId);
        _validateTimestampHasNotPassed(standardOrder.fillDeadline);
        _validateTimestampHasNotPassed(standardOrder.expires);

        bytes32 orderId = this.orderIdentifier(standardOrder);

        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();
        // Mark order as deposited
        orderStatus[orderId] = OrderStatus.Deposited;

        // Handle native ETH collection directly (bypass parent's open)
        _openNativeETH(standardOrder);

        // Validate that there has been no reentrancy
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        // Store refund calldata hash
        orderRefundCalldata[orderId] = extendedOrder.refundCalldataHash;

        emit Open(orderId, standardOrder);
        emit ExtendedOpen(orderId, extendedOrder.refundCalldataHash);
    }

    /**
     * @notice Internal function to handle native ETH collection
     * @param order StandardOrder containing the transfer details
     */
    function _openNativeETH(
        StandardOrder memory order
    ) internal {
        // Collect input tokens with native ETH support
        uint256[2][] memory inputs = order.inputs;
        uint256 numInputs = inputs.length;
        uint256 expectedEthValue = 0;
        
        for (uint256 i = 0; i < numInputs; ++i) {
            uint256[2] memory input = inputs[i];
            address token = input[0].validatedCleanAddress();
            uint256 amount = input[1];
            
            if (token == address(0)) {
                // Native ETH - accumulate expected value (ETH is sent via msg.value)
                expectedEthValue += amount;
            } else {
                // For Shinobi.cash, we focus on native ETH only
                // If ERC20 support is needed later, add SafeERC20.safeTransferFrom here
                revert("Only native ETH supported in Shinobi ExtendedInputSettler");
            }
        }
        
        // Verify sufficient ETH was sent with the transaction
        if (msg.value < expectedEthValue) {
            revert("Insufficient ETH amount sent");
        }
        
        // ETH is now held in this contract - no additional transfers needed
    }

    /**
     * @notice Execute custom refund logic
     * @param inputs Array of input tokens to refund
     * @param target Target contract for refund execution
     * @param functionCalldata Calldata to execute on target
     */
    function _executeCustomRefund(
        uint256[2][] calldata inputs,
        address target,
        bytes memory functionCalldata
    ) internal {
        // Approve ERC20 tokens for target contract
        uint256 ethToSend = 0;
        
        for (uint256 i = 0; i < inputs.length; i++) {
            address token = address(uint160(inputs[i][0]));
            uint256 amount = inputs[i][1];
            
            if (token == address(0)) {
                ethToSend += amount;
            } else {
                IERC20(token).approve(target, amount);
            }
        }

        // Execute custom refund calldata with ETH
        (bool success,) = target.call{value: ethToSend}(functionCalldata);
        if (!success) revert RefundExecutionFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERFACE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the refund calldata hash for an order
     * @param orderId The order identifier
     * @return The committed refund calldata hash
     */
    function getRefundCalldataHash(bytes32 orderId) external view override returns (bytes32) {
        return orderRefundCalldata[orderId];
    }

    /**
     * @notice Generate order identifier for extended order
     * @param order The extended order data
     * @return The unique order identifier
     */
    function extendedOrderIdentifier(ExtendedOrder memory order) external view override returns (bytes32) {
        StandardOrder memory standardOrder = order.toStandardOrder();
        return this.orderIdentifier(standardOrder);
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow contract to receive ETH
    receive() external payable {}
}