// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {WithdrawFacet} from "../../src/diamond/facets/WithdrawFacet.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract WithdrawFacetTest is DiamondTestBase {
    function setUp() public override {
        super.setUp();
        // Make a deposit so there's something to withdraw
        _deposit(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_withdraw_success() public {
        address recipient = makeAddr("recipient");
        uint256 withdrawValue = 0.5 ether;
        uint256 relayFeeBPS = 100; // 1%

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient,
                feeRecipient: feeRecipient,
                relayFeeBPS: relayFeeBPS
            }))
        });

        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, withdrawValue, 222);
        proof.pubSignals[7] = _computeContext(withdrawal); // context

        // Fund diamond to cover withdrawal
        vm.deal(address(diamond), 10 ether);

        uint256 recipientBefore = recipient.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // Verify recipient received amount minus fee
        uint256 fee = withdrawValue * relayFeeBPS / 10_000;
        assertEq(recipient.balance - recipientBefore, withdrawValue - fee);
        assertEq(feeRecipient.balance - feeBefore, fee);

        // Verify nullifier is spent
        assertTrue(pool.nullifierHashes(111));
    }

    function test_withdraw_revertsForInvalidProcessooor() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(0xdead),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);

        vm.expectRevert(WithdrawFacet.InvalidProcessooor.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForZeroValue() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0, 222);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForInvalidProof() public {
        withdrawalVerifier.setShouldPass(false);

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(WithdrawFacet.InvalidProof.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForSpentNullifier() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.deal(address(diamond), 10 ether);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // Try to spend same nullifier again
        ProofLib.WithdrawProof memory proof2 = _makeWithdrawProof(111, 0.5 ether, 333);
        proof2.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof2);
    }

    function test_withdraw_revertsForExcessiveRelayFee() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, MAX_RELAY_FEE_BPS + 1)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(WithdrawFacet.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForContextMismatch() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = 12345; // wrong context

        vm.expectRevert(PoolOps.ContextMismatch.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForUnknownStateRoot() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[3] = 99999; // unknown state root
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.UnknownStateRoot.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForIncorrectASPRoot() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[5] = 99999; // wrong ASP root
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.IncorrectASPRoot.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_revertsForInvalidTreeDepth() public {
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[4] = 33; // exceeds MAX_TREE_DEPTH (32)
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.expectRevert(PoolOps.InvalidTreeDepth.selector);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);
    }

    function test_withdraw_withZeroRelayFee() public {
        address recipient = makeAddr("recipient");

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(recipient, 0)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.deal(address(diamond), 10 ether);
        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // Full amount goes to recipient
        assertEq(recipient.balance - recipientBefore, 0.5 ether);
    }

    function test_withdraw_insertsNewCommitment() public {
        uint256 treeSizeBefore = pool.currentTreeSize();

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(user, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.deal(address(diamond), 10 ether);
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // New commitment (change) should be in tree
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_withdraw_worksWhenPoolIsDead() public {
        vm.prank(admin);
        pool.windDown();
        assertTrue(pool.dead());

        address recipient = makeAddr("recipient");
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeRelayData(recipient, 100)
        });
        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        vm.deal(address(diamond), 10 ether);
        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        uint256 fee = 0.5 ether * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, 0.5 ether - fee);
    }
}
