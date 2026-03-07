// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {Withdraw2Action} from "../../src/pool/facets/Withdraw2Action.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {WithdrawData} from "../../src/pool/libraries/Types.sol";
import {Withdraw2ProofLib} from "../../src/proofLibs/Withdraw2ProofLib.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

contract Withdraw2ActionTest is PoolTestBase {
    uint256 constant WITHDRAW_VALUE = 1.5 ether;

    function setUp() public override {
        super.setUp();
        // Two deposits so there are two commitments to merge
        _deposit(user, DEPOSIT_AMOUNT, 12345);
        _deposit(user, DEPOSIT_AMOUNT, 12346);
        // Fund pool for withdrawals
        vm.deal(address(pool), 10 ether);
    }

    function test_withdraw2_success() public {
        address recipient = makeAddr("recipient");
        uint256 relayFeeBPS = 100;

        WithdrawData memory data = WithdrawData({
            recipient: recipient,
            feeRecipient: feeRecipient,
            relayFeeBPS: relayFeeBPS
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        uint256 recipientBefore = recipient.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);

        uint256 fee = WITHDRAW_VALUE * relayFeeBPS / 10_000;
        assertEq(recipient.balance - recipientBefore, WITHDRAW_VALUE - fee);
        assertEq(feeRecipient.balance - feeBefore, fee);
        assertTrue(poolInterface.nullifierHashes(111));
        assertTrue(poolInterface.nullifierHashes(222));
    }

    function test_withdraw2_revertsForZeroValue() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, 0, 333);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);
    }

    function test_withdraw2_revertsForInvalidProof() public {
        withdraw2Verifier.setShouldPass(false);

        WithdrawData memory data = _makeWithdrawData(user, 100);
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.expectRevert(Withdraw2Action.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);
    }

    function test_withdraw2_revertsForSpentNullifier() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);

        // Second attempt with same nullifier0
        Withdraw2ProofLib.Withdraw2Proof memory proof2 = _makeWithdraw2Proof(111, 444, WITHDRAW_VALUE, 555);
        proof2.pubSignals[8] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof2);
    }

    function test_withdraw2_revertsForDuplicateNullifiers() public {
        WithdrawData memory data = _makeWithdrawData(user, 100);

        // Same nullifier for both
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 111, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);
    }

    function test_withdraw2_revertsForExcessiveRelayFee() public {
        WithdrawData memory data = _makeWithdrawData(user, MAX_RELAY_FEE_BPS + 1);

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.expectRevert(Withdraw2Action.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);
    }

    function test_withdraw2_revertsForZeroRelayFee() public {
        address recipient = makeAddr("recipient");

        WithdrawData memory data = _makeWithdrawData(recipient, 0);

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.expectRevert(Withdraw2Action.RelayFeeBPSZero.selector);
        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);
    }

    function test_withdraw2_insertsNewCommitment() public {
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        WithdrawData memory data = _makeWithdrawData(user, 100);

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(abi.encode(data));

        vm.prank(relayer);
        poolInterface.withdraw2(data, proof);

        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }
}
