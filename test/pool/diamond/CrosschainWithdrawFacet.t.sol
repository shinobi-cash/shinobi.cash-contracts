// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase, MockInputSettler} from "./DiamondTestBase.sol";
import {CrosschainWithdrawFacet} from "../../../src/pool/facets/CrosschainWithdrawFacet.sol";
import {PoolOps} from "../../../src/pool/libraries/PoolOps.sol";
import {RefundOps} from "../../../src/pool/libraries/RefundOps.sol";
import {CrosschainWithdrawData} from "../../../src/pool/libraries/Types.sol";
import {CrosschainProofLib} from "../../../src/proofLibs/CrosschainProofLib.sol";
import {Constants} from "../../../src/pool/libraries/Constants.sol";

contract CrosschainWithdrawFacetTest is DiamondTestBase {
    uint256 constant WITHDRAW_VALUE = 0.5 ether;
    uint256 constant RELAY_FEE_BPS = 100; // 1%
    uint256 constant SOLVER_FEE_BPS = 200; // 2%
    uint256 constant REFUND_FEE_BPS = 50; // 0.5%
    address recipient = makeAddr("ccRecipient");

    function setUp() public override {
        super.setUp();
        _deposit(user, DEPOSIT_AMOUNT, 12345);
        _setupCrosschainConfig();
        vm.deal(address(diamond), 10 ether);
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
        pool.crosschainWithdraw(data, proof);

        // Nullifier spent
        assertTrue(pool.nullifierHashes(111));

        // Relay fee paid to feeRecipient
        uint256 relayFee = WITHDRAW_VALUE * RELAY_FEE_BPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, relayFee);

        // Settler was called with escrow
        assertEq(mockSettler.openCallCount(), settlerCallsBefore + 1);
    }

    function test_crosschainWithdraw_revertsForMaxSolverFeeNotSet() public {
        // Reset maxSolverFeeBPS to 0
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(0);

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.expectRevert(CrosschainWithdrawFacet.MaxSolverFeeBPSNotSet.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForZeroValue() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, 0, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForChainNotConfigured() public {
        uint256 unconfiguredChain = 99999;

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, unconfiguredChain, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawFacet.DestinationChainNotConfigured.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForExcessiveRelayFee() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        // relayFeeBPS exceeds max
        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, MAX_RELAY_FEE_BPS + 1, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawFacet.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForExcessiveSolverFee() public {
        uint256 maxSolver = pool.maxSolverFeeBPS();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(maxSolver + 1, DEST_CHAIN_ID, recipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 222, 333, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdrawFacet.SolverFeeGreaterThanMax.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForInvalidProof() public {
        crosschainVerifier.setShouldPass(false);

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.expectRevert(CrosschainWithdrawFacet.InvalidProof.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_crosschainWithdraw_revertsForSpentNullifier() public {
        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);

        // Same nullifier again
        CrosschainProofLib.CrosschainWithdrawProof memory proof2 =
            _makeCrosschainWithdrawProof(111, WITHDRAW_VALUE, 444, 555, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof2.pubSignals[10] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof2);
    }

    function test_crosschainWithdraw_insertsNewCommitment() public {
        uint256 treeSizeBefore = pool.currentTreeSize();

        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);

        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }

    function test_crosschainWithdraw_escrowsCorrectAmount() public {
        (CrosschainWithdrawData memory data, CrosschainProofLib.CrosschainWithdrawProof memory proof) =
            _buildWithdrawalAndProof();

        uint256 settlerBalanceBefore = address(mockSettler).balance;

        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);

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

        vm.expectRevert(CrosschainWithdrawFacet.RefundFeeGreaterThanMax.selector);
        vm.prank(relayer);
        pool.crosschainWithdraw(data, proof);
    }

    function test_handleRefund_revertsForExcessiveRefundFee() public {
        uint256 scope = pool.SCOPE();

        vm.expectRevert(RefundOps.RefundFeeGreaterThanMax.selector);
        vm.prank(address(mockSettler));
        pool.handleRefund{value: 1 ether}(42, feeRecipient, MAX_RELAY_FEE_BPS + 1, scope);
    }

    function test_handleRefund_success() public {
        uint256 scope = pool.SCOPE();
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 100; // 1%
        uint256 treeSizeBefore = pool.currentTreeSize();
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(address(mockSettler));
        pool.handleRefund{value: refundAmount}(42, feeRecipient, refundFeeBPS, scope);

        // Commitment inserted
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
        // Fee paid
        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);
    }
}
