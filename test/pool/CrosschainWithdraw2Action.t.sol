// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {CrosschainWithdraw2Action} from "../../src/pool/facets/CrosschainWithdraw2Action.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {IntentOps} from "../../src/pool/libraries/IntentOps.sol";
import {CrosschainWithdrawData} from "../../src/pool/libraries/Types.sol";
import {CrosschainWithdraw2ProofLib} from "../../src/proofLibs/CrosschainWithdraw2ProofLib.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

contract CrosschainWithdraw2ActionTest is PoolTestBase {
    uint256 constant WITHDRAW_VALUE = 1.5 ether;
    uint256 constant RELAY_FEE_BPS = 100;
    uint256 constant SOLVER_FEE_BPS = 200;
    uint256 constant REFUND_FEE_BPS = 50;
    address recipient = makeAddr("ccRecipient2");

    function setUp() public override {
        super.setUp();
        _deposit(user, DEPOSIT_AMOUNT, 12345);
        _deposit(user, DEPOSIT_AMOUNT, 12346);
        _setupCrosschainConfig();
        vm.deal(address(pool), 10 ether);
    }

    function _buildWithdrawalAndProof()
        internal
        view
        returns (
            CrosschainWithdrawData memory data,
            CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof
        )
    {
        data = _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        proof = _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));
    }

    function test_crosschainWithdraw2_success() public {
        (
            CrosschainWithdrawData memory data,
            CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof
        ) = _buildWithdrawalAndProof();

        uint256 feeBefore = feeRecipient.balance;
        uint256 settlerCallsBefore = mockSettler.openCallCount();

        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);

        // Both nullifiers spent
        assertTrue(poolInterface.nullifierHashes(111));
        assertTrue(poolInterface.nullifierHashes(222));

        // Relay fee paid
        uint256 relayFee = WITHDRAW_VALUE * RELAY_FEE_BPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, relayFee);

        // Settler called
        assertEq(mockSettler.openCallCount(), settlerCallsBefore + 1);
    }

    function test_crosschainWithdraw2_revertsForZeroValue() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, 0, 333, 444, RELAY_FEE_BPS, REFUND_FEE_BPS);

        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForDuplicateNullifiers() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 111, WITHDRAW_VALUE, 333, 444, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForChainNotConfigured() public {
        uint256 unconfiguredChain = 99999;

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, unconfiguredChain, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdraw2Action.DestinationChainNotConfigured.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForExcessiveRelayFee() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, MAX_RELAY_FEE_BPS + 1, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdraw2Action.RelayFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForExcessiveSolverFee() public {
        uint256 maxSolver = poolInterface.maxSolverFeeBPS();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(maxSolver + 1, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdraw2Action.SolverFeeGreaterThanMax.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForZeroRefundCommitment() public {
        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(SOLVER_FEE_BPS, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 0, RELAY_FEE_BPS, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(CrosschainWithdraw2Action.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForCombinedFeesTooHigh() public {
        vm.startPrank(admin);
        poolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, 9000);
        poolInterface.setMaxSolverFeeBPS(9000);
        vm.stopPrank();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(5000, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, 5000, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        vm.expectRevert(IntentOps.CombinedFeesTooHigh.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_combinedFeeCheckBeforeProofVerification() public {
        crosschainWithdraw2Verifier.setShouldPass(false);

        vm.startPrank(admin);
        poolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, 9000);
        poolInterface.setMaxSolverFeeBPS(9000);
        vm.stopPrank();

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(5000, DEST_CHAIN_ID, recipient);

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof =
            _makeCrosschainWithdraw2Proof(111, 222, WITHDRAW_VALUE, 333, 444, 5000, REFUND_FEE_BPS);
        proof.pubSignals[11] = _computeContext(abi.encode(data));

        // Should revert with CombinedFeesTooHigh, NOT InvalidProof
        vm.expectRevert(IntentOps.CombinedFeesTooHigh.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_revertsForInvalidProof() public {
        crosschainWithdraw2Verifier.setShouldPass(false);

        (
            CrosschainWithdrawData memory data,
            CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof
        ) = _buildWithdrawalAndProof();

        vm.expectRevert(CrosschainWithdraw2Action.InvalidProof.selector);
        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);
    }

    function test_crosschainWithdraw2_insertsNewCommitment() public {
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        (
            CrosschainWithdrawData memory data,
            CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof
        ) = _buildWithdrawalAndProof();

        vm.prank(relayer);
        poolInterface.crosschainWithdraw2(data, proof);

        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }
}
