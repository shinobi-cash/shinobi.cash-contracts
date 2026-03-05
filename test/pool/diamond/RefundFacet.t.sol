// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {RefundOps} from "../../../src/pool/libraries/RefundOps.sol";

contract RefundFacetTest is DiamondTestBase {
    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        pool.setMaxRefundFeeBPS(500);
    }

    function test_handleRefund_success() public {
        uint256 refundCommitment = 42;
        uint256 refundFeeBPS = 100; // 1%
        uint256 refundAmount = 1 ether;
        uint256 scope = pool.SCOPE();

        uint256 feeBefore = feeRecipient.balance;
        uint256 treeSizeBefore = pool.currentTreeSize();

        vm.prank(address(mockSettler));
        pool.handleRefund{value: refundAmount}(refundCommitment, feeRecipient, refundFeeBPS, scope);

        // Fee should be paid
        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);

        // Commitment should be inserted
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_handleRefund_revertsForNonSettler() public {
        uint256 scope = pool.SCOPE();
        vm.expectRevert(RefundOps.OnlyWithdrawalInputSettler.selector);
        vm.prank(user);
        pool.handleRefund{value: 1 ether}(42, feeRecipient, 100, scope);
    }

    function test_handleRefund_revertsForWrongScope() public {
        vm.expectRevert(RefundOps.ScopeMismatch.selector);
        vm.prank(address(mockSettler));
        pool.handleRefund{value: 1 ether}(42, feeRecipient, 100, 999);
    }

    function test_handleRefund_zeroFee() public {
        uint256 treeSizeBefore = pool.currentTreeSize();
        uint256 scope = pool.SCOPE();

        vm.prank(address(mockSettler));
        pool.handleRefund{value: 1 ether}(42, feeRecipient, 0, scope);

        // No fee deducted, commitment still inserted
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }
}
