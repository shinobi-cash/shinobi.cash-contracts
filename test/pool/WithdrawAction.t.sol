// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {WithdrawAction} from "../../src/pool/facets/WithdrawAction.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {WithdrawData} from "../../src/pool/libraries/Types.sol";
import {WithdrawProofLib} from "../../src/proofLibs/WithdrawProofLib.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

contract WithdrawActionTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        // Make a deposit so there's something to withdraw
        _deposit(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_withdraw_success() public {
        address recipient = makeAddr("recipient");
        uint256 withdrawValue = 0.5 ether;
        uint256 relayFeeBPS = 100; // 1%

        WithdrawData memory data = WithdrawData({
            recipient: recipient,
            feeRecipient: feeRecipient,
            relayFeeBPS: relayFeeBPS
        });

        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, withdrawValue, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data)); // context

        // Fund pool to cover withdrawal
        vm.deal(address(pool), 10 ether);

        uint256 recipientBefore = recipient.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        // Verify recipient received amount minus fee
        uint256 fee = withdrawValue * relayFeeBPS / 10_000;
        assertEq(recipient.balance - recipientBefore, withdrawValue - fee);
        assertEq(feeRecipient.balance - feeBefore, fee);

        // Verify nullifier is spent
        assertTrue(poolInterface.nullifierHashes(111));
    }

    function test_withdraw_revertsForZeroValue() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0, 222);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForInvalidProof() public {
        withdrawalVerifier.setShouldPass(false);

        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(WithdrawAction.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForSpentNullifier() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.deal(address(pool), 10 ether);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        // Try to spend same nullifier again
        WithdrawProofLib.WithdrawProof memory proof2 = _makeWithdrawProof(111, 0.5 ether, 333);
        proof2.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof2);
    }

    function test_withdraw_revertsForExcessiveRelayFee() public {
        WithdrawData memory data = _makeWithdrawData(user, MAX_RELAY_FEE_BPS + 1);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(WithdrawAction.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForContextMismatch() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = 12345; // wrong context

        vm.expectRevert(PoolOps.ContextMismatch.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForUnknownStateRoot() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[3] = 99999; // unknown state root
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.UnknownStateRoot.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForIncorrectASPRoot() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[5] = 99999; // wrong ASP root
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.IncorrectASPRoot.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForInvalidTreeDepth() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[4] = 33; // exceeds MAX_TREE_DEPTH (32)
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.InvalidTreeDepth.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_revertsForZeroRelayFee() public {
        address recipient = makeAddr("recipient");

        WithdrawData memory data = _makeWithdrawData(recipient, 0);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.deal(address(pool), 10 ether);

        vm.expectRevert(WithdrawAction.RelayFeeBPSZero.selector);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);
    }

    function test_withdraw_insertsNewCommitment() public {
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        WithdrawData memory data = _makeWithdrawData(user, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.deal(address(pool), 10 ether);
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        // New commitment (change) should be in tree
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_withdraw_worksWhenPoolIsDead() public {
        vm.prank(admin);
        poolInterface.windDown();
        assertTrue(poolInterface.dead());

        address recipient = makeAddr("recipient");
        WithdrawData memory data = _makeWithdrawData(recipient, 100);
        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.deal(address(pool), 10 ether);
        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        uint256 fee = 0.5 ether * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, 0.5 ether - fee);
    }
}
