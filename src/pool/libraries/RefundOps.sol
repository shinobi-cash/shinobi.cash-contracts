// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolStorageData} from "../storage/PoolStorage.sol";
import {PoolOps} from "./PoolOps.sol";

/// @title RefundOps - Shared refund logic for crosschain withdrawal facets
library RefundOps {
    event Refunded(uint256 amount, uint256 indexed refundCommitment, uint256 refundFee, address indexed feeRecipient);
    event RefundFeeTransferFailed(address indexed feeRecipient, uint256 amount);

    error OnlyWithdrawalInputSettler();
    error ScopeMismatch();
    error RefundFeeGreaterThanMax();

    function executeRefund(
        PoolStorageData storage ps,
        uint256 refundCommitment,
        address feeRecipient,
        uint256 refundFeeBPS,
        uint256 scope
    ) internal {
        if (msg.sender != ps.withdrawalInputSettler) revert OnlyWithdrawalInputSettler();
        if (scope != ps.scope) revert ScopeMismatch();
        if (refundFeeBPS > ps.maxRefundFeeBPS) revert RefundFeeGreaterThanMax();

        uint256 refundFee = PoolOps.calculateFee(msg.value, refundFeeBPS);
        uint256 refundAmount = msg.value - refundFee;

        // State changes first (CEI pattern)
        PoolOps.insert(ps, refundCommitment);

        // External interaction last — non-reverting to prevent a non-payable
        // feeRecipient from permanently locking the refund commitment
        if (refundFee > 0) {
            (bool ok,) = feeRecipient.call{value: refundFee}("");
            if (!ok) emit RefundFeeTransferFailed(feeRecipient, refundFee);
        }

        emit Refunded(refundAmount, refundCommitment, refundFee, feeRecipient);
    }
}
