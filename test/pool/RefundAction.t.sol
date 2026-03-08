// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {RefundOps} from "../../src/pool/libraries/RefundOps.sol";

contract RefundActionTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        poolInterface.setMaxRefundFeeBPS(500);
    }

    function test_handleRefund_success() public {
        uint256 refundCommitment = 42;
        uint256 refundFeeBPS = 100; // 1%
        uint256 refundAmount = 1 ether;
        uint256 scope = poolInterface.SCOPE();

        uint256 feeBefore = feeRecipient.balance;
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: refundAmount}(refundCommitment, feeRecipient, refundFeeBPS, scope);

        // Fee should be paid
        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);

        // Commitment should be inserted
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_handleRefund_revertsForNonSettler() public {
        uint256 scope = poolInterface.SCOPE();
        vm.expectRevert(RefundOps.OnlyWithdrawalInputSettler.selector);
        vm.prank(user);
        poolInterface.handleRefund{value: 1 ether}(42, feeRecipient, 100, scope);
    }

    function test_handleRefund_revertsForWrongScope() public {
        vm.expectRevert(RefundOps.ScopeMismatch.selector);
        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: 1 ether}(42, feeRecipient, 100, 999);
    }

    function test_handleRefund_zeroFee() public {
        uint256 treeSizeBefore = poolInterface.currentTreeSize();
        uint256 scope = poolInterface.SCOPE();

        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: 1 ether}(42, feeRecipient, 0, scope);

        // No fee deducted, commitment still inserted
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_handleRefund_nonPayableFeeRecipient_stillSucceeds() public {
        // Deploy a contract that rejects ETH
        NonPayableContract rejecter = new NonPayableContract();
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 100; // 1%
        uint256 scope = poolInterface.SCOPE();

        uint256 poolBalBefore = address(pool).balance;
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        vm.expectEmit(true, false, false, true);
        emit RefundOps.RefundFeeTransferFailed(address(rejecter), refundAmount * refundFeeBPS / 10_000);

        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: refundAmount}(42, address(rejecter), refundFeeBPS, scope);

        // Commitment should still be inserted
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
        // Fee stays in pool as surplus (full refundAmount retained)
        assertEq(address(pool).balance - poolBalBefore, refundAmount);
        assertEq(address(rejecter).balance, 0);
    }

    function test_handleRefund_refundFeeExceedsMax_reverts() public {
        uint256 scope = poolInterface.SCOPE();
        vm.expectRevert(RefundOps.RefundFeeGreaterThanMax.selector);
        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: 1 ether}(42, feeRecipient, 501, scope); // max is 500
    }
}

contract NonPayableContract {
    // Intentionally does not have receive() or fallback()
}
