// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title RefundFacet - Handle refunds for failed cross-chain intents
contract RefundFacet is FacetBase, IFacet {
    event Refunded(uint256 amount, uint256 indexed refundCommitmentHash, uint256 refundFee, address indexed feeRecipient);
    event RefundCommitmentInserted(uint256 indexed refundCommitmentHash, uint256 amount);

    error OnlyWithdrawalInputSettler();
    error ScopeMismatch();
    error RefundFeeTransferFailed();

    /// @notice Handle a refund from the input settler for a failed intent
    function handleRefund(uint256 refundCommitmentHash, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable
        nonReentrant
    {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (msg.sender != s.withdrawalInputSettler) revert OnlyWithdrawalInputSettler();
        if (scope != s.scope) revert ScopeMismatch();

        uint256 refundFee = PoolOps.calculateFee(msg.value, refundFeeBPS);
        uint256 refundAmount = msg.value - refundFee;

        if (refundFee > 0) {
            PoolOps.transferETH(feeRecipient, refundFee);
        }

        PoolOps.insert(s, refundCommitmentHash);

        emit RefundCommitmentInserted(refundCommitmentHash, refundAmount);
        emit Refunded(refundAmount, refundCommitmentHash, refundFee, feeRecipient);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.handleRefund.selector);
    }
}
