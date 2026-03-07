// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase, MockInputSettler} from "./PoolTestBase.sol";
import {CrosschainWithdrawAction} from "../../src/pool/facets/CrosschainWithdrawAction.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {IntentOps} from "../../src/pool/libraries/IntentOps.sol";
import {RefundOps} from "../../src/pool/libraries/RefundOps.sol";
import {CrosschainWithdrawData} from "../../src/pool/libraries/Types.sol";
import {CrosschainProofLib} from "../../src/proofLibs/CrosschainProofLib.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

contract CrosschainWithdrawActionTest is PoolTestBase {
    uint256 constant WITHDRAW_VALUE = 0.5 ether;
    uint256 constant RELAY_FEE_BPS = 100; // 1%
    uint256 constant SOLVER_FEE_BPS = 200; // 2%
    uint256 constant REFUND_FEE_BPS = 50; // 0.5%
    address recipient = makeAddr("ccRecipient");

    function setUp() public override {
        super.setUp();
        _deposit(user, DEPOSIT_AMOUNT, 12345);
        _setupCrosschainConfig();
        vm.deal(address(pool), 10 ether);
    }

    function _buildWithdrawalAndProof()
        internal
        view
        returns (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof)
    {
        data = _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        proof = _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));
    }

    function test_crosschainWithdraw_success() public {
        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        uint256 feeBefore = feeRecipient.balance;
        uint256 settlerCallsBefore = mockSettler.openCallCount();

        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);

        // Nullifier spent
        assertTrue(poolInterface.nullifierHashes(111));

        // Relay fee paid to feeRecipient
        uint256 relayFee = WITHDRAW_VALUE * RELAY_FEE_BPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, relayFee);

        // Settler was called with escrow
        assertEq(mockSettler.openCallCount(), settlerCallsBefore + 1);
    }

    function test_crosschainWithdraw_revertsForMaxSolverFeeNotSet() public {
        // Reset maxSolverFeeBPS to 0
        vm.prank(admin);
        poolInterface.setMaxSolverFeeBPS(0);

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.expectRevert(CrosschainWithdrawAction.MaxSolverFeeBPSNotSet.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForZeroValue() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, 0, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForChainNotConfigured() public {
        uint256 unconfiguredChain = 99999;

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, unconfiguredChain, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawAction.DestinationChainNotConfigured.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForExcessiveRelayFee() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        // relayFeeBPS exceeds max
        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, MAX_RELAY_FEE_BPS + 1, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawAction.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForExcessiveSolverFee() public {
        uint256 maxSolver = poolInterface.maxSolverFeeBPS();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(maxSolver + 1, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawAction.SolverFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForInvalidProof() public {
        crosschainVerifier.setShouldPass(false);

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.expectRevert(CrosschainWithdrawAction.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForSpentNullifier() public {
        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);

        // Same nullifier again
        CrosschainProofLib.CrosschainWithdrawProof memory proof2 =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 444, 555, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof2.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof2);
    }

    function test_crosschainWithdraw_insertsNewCommitment() public {
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);

        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_crosschainWithdraw_escrowsCorrectAmount() public {
        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        uint256 settlerBalanceBefore = address(mockSettler).balance;

        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);

        // escrowAmount = withdrawnValue - relayFee
        uint256 relayFee = WITHDRAW_VALUE * RELAY_FEE_BPS / 10_000;
        uint256 escrowAmount = WITHDRAW_VALUE - relayFee;
        assertEq(address(mockSettler).balance - settlerBalanceBefore, escrowAmount);
    }

    function test_crosschainWithdraw_revertsForExcessiveRefundFee() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        // refundFeeBPS exceeds maxRelayFeeBPS
        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, MAX_RELAY_FEE_BPS + 1);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawAction.RefundFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForZeroRefundCommitment() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 0, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawAction.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForCombinedFeesTooHigh() public {
        // Set high max limits so individual checks pass
        vm.startPrank(admin);
        poolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, 9000);
        poolInterface.setMaxSolverFeeBPS(9000);
        vm.stopPrank();

        // relayFeeBPS=5000 + solverFeeBPS=5000 = 10000 >= 10000
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(5000, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, 5000, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(IntentOps.CombinedFeesTooHigh.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_combinedFeeCheckBeforeProofVerification() public {
        crosschainVerifier.setShouldPass(false);

        vm.startPrank(admin);
        poolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, 9000);
        poolInterface.setMaxSolverFeeBPS(9000);
        vm.stopPrank();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(5000, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, 5000, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        // Should revert with CombinedFeesTooHigh, NOT InvalidProof
        vm.expectRevert(IntentOps.CombinedFeesTooHigh.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);
    }

    function test_handleRefund_revertsForExcessiveRefundFee() public {
        uint256 scope = poolInterface.SCOPE();

        vm.expectRevert(RefundOps.RefundFeeGreaterThanMax.selector);
        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: 1 ether}(42, feeRecipient, MAX_RELAY_FEE_BPS + 1, scope);
    }

    function test_handleRefund_success() public {
        uint256 scope = poolInterface.SCOPE();
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 100; // 1%
        uint256 treeSizeBefore = poolInterface.currentTreeSize();
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: refundAmount}(42, feeRecipient, refundFeeBPS, scope);

        // Commitment inserted
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
        // Fee paid
        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);
    }
}
