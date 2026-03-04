// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {Withdraw2Facet} from "../../src/diamond/facets/Withdraw2Facet.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {Withdraw2ProofLib} from "../../src/core/libraries/Withdraw2ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract Withdraw2FacetTest is DiamondTestBase {
    uint256 constant WITHDRAW_VALUE = 1.5 ether;

    function setUp() public override {
        super.setUp();
        // Two deposits so there are two commitments to merge
        _deposit(user, DEPOSIT_AMOUNT, 12345);
        _deposit(user, DEPOSIT_AMOUNT, 12346);
        // Fund diamond for withdrawals
        vm.deal(address(diamond), 10 ether);
    }

    function test_withdraw2_success() public {
        address recipient = makeAddr("recipient");
        uint256 relayFeeBPS = 100;

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(recipient, relayFeeBPS)
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        uint256 recipientBefore = recipient.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);

        uint256 fee = WITHDRAW_VALUE * relayFeeBPS / 10_000;
        assertEq(recipient.balance - recipientBefore, WITHDRAW_VALUE - fee);
        assertEq(feeRecipient.balance - feeBefore, fee);
        assertTrue(pool.nullifierHashes(111));
        assertTrue(pool.nullifierHashes(222));
    }

    function test_withdraw2_revertsForInvalidProcessooor() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(0xdead),
            data: _makeRelayData(user, 100)
        });
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);

        vm.expectRevert(Withdraw2Facet.InvalidProcessooor.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);
    }

    function test_withdraw2_revertsForZeroValue() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, 0, 333);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);
    }

    function test_withdraw2_revertsForInvalidProof() public {
        withdraw2Verifier.setShouldPass(false);

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        vm.expectRevert(Withdraw2Facet.InvalidProof.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);
    }

    function test_withdraw2_revertsForSpentNullifier() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);

        // Second attempt with same nullifier0
        Withdraw2ProofLib.Withdraw2Proof memory proof2 = _makeWithdraw2Proof(111, 444, WITHDRAW_VALUE, 555);
        proof2.pubSignals[8] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof2);
    }

    function test_withdraw2_revertsForDuplicateNullifiers() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });

        // Same nullifier for both
        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 111, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);
    }

    function test_withdraw2_revertsForExcessiveRelayFee() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, MAX_RELAY_FEE_BPS + 1)
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        vm.expectRevert(Withdraw2Facet.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);
    }

    function test_withdraw2_withZeroRelayFee() public {
        address recipient = makeAddr("recipient");

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(recipient, 0)
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);

        // Full amount goes to recipient with no fee
        assertEq(recipient.balance - recipientBefore, WITHDRAW_VALUE);
    }

    function test_withdraw2_insertsNewCommitment() public {
        uint256 treeSizeBefore = pool.currentTreeSize();

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });

        Withdraw2ProofLib.Withdraw2Proof memory proof = _makeWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333);
        proof.pubSignals[8] = _computeContext(withdrawal);

        vm.prank(relayer);
        pool.withdraw2(withdrawal, proof);

        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }
}
