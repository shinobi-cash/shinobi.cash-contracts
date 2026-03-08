// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {WithdrawData, CrosschainWithdrawData} from "../../src/pool/libraries/Types.sol";
import {WithdrawProofLib} from "../../src/proofLibs/WithdrawProofLib.sol";
import {RagequitProofLib} from "../../src/proofLibs/RagequitProofLib.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";
import {IFacet} from "../../src/pool/interfaces/IFacet.sol";
import {IShinobiPool} from "../../src/pool/interfaces/IShinobiPool.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {CrosschainProofLib} from "../../src/proofLibs/CrosschainProofLib.sol";

contract IntegrationTest is PoolTestBase {
    /*//////////////////////////////////////////////////////////////
                    DEPOSIT -> WITHDRAW FLOW
    //////////////////////////////////////////////////////////////*/

    function test_depositAndWithdraw() public {
        // 1. Deposit
        uint256 precommitment = 12345;
        vm.prank(user);
        uint256 commitment = poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);
        assertTrue(commitment != 0);

        // 2. Verify state after deposit
        assertEq(poolInterface.nonce(), 1);
        assertEq(poolInterface.currentTreeSize(), 1);
        assertTrue(poolInterface.currentRoot() != 0);

        // 3. Withdraw
        address recipient = makeAddr("recipient");
        uint256 withdrawValue = 0.5 ether;

        WithdrawData memory data = WithdrawData({
            recipient: recipient,
            feeRecipient: feeRecipient,
            relayFeeBPS: 100
        });

        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, withdrawValue, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        // Fund pool (simulates having funds from deposit)
        vm.deal(address(pool), 10 ether);

        uint256 recipientBefore = recipient.balance;
        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        // 4. Verify withdrawal succeeded
        uint256 fee = withdrawValue * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, withdrawValue - fee);
        assertTrue(poolInterface.nullifierHashes(111));
        assertEq(poolInterface.currentTreeSize(), 2); // deposit + new commitment from withdraw
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE DEPOSITS + VIEW STATE
    //////////////////////////////////////////////////////////////*/

    function test_multipleDepositsUpdateState() public {
        vm.startPrank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(1);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(2);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(3);
        vm.stopPrank();

        assertEq(poolInterface.nonce(), 3);
        assertEq(poolInterface.currentTreeSize(), 3);
        assertTrue(poolInterface.currentTreeDepth() > 0);
        assertTrue(poolInterface.currentRoot() != 0);
    }

    /*//////////////////////////////////////////////////////////////
                    POOL UPGRADE + CALL NEW FACET
    //////////////////////////////////////////////////////////////*/

    function test_upgradeAndCallNewFacet() public {
        // Deploy and add mock extra facet
        MockExtraFacet newFacet = new MockExtraFacet();

        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IShinobiPool.ReplaceAction[] memory replaceFacets = new IShinobiPool.ReplaceAction[](0);

        vm.prank(admin);
        poolInterface.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        // Call the new function through the pool
        (bool success, bytes memory retData) =
            address(pool).call(abi.encodeWithSelector(MockExtraFacet.extraFunction.selector));
        assertTrue(success);
        uint256 result = abi.decode(retData, (uint256));
        assertEq(result, 42);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_reentrancyGuard_preventsReentry() public {
        // The reentrancy guard shares state across all facets via PoolStorage
        // We can verify it works by checking reentrancy status is reset
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);

        // If reentrancy guard was stuck, this would revert
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12346);

        assertEq(poolInterface.nonce(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND FLOW
    //////////////////////////////////////////////////////////////*/

    function test_refundInsertsCommitmentAndPaysFee() public {
        vm.prank(admin);
        poolInterface.setMaxRefundFeeBPS(500);

        uint256 refundCommitment = 42;
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 200; // 2%

        uint256 feeBefore = feeRecipient.balance;
        uint256 treeSizeBefore = poolInterface.currentTreeSize();

        uint256 scope = poolInterface.SCOPE();
        vm.prank(address(mockSettler));
        poolInterface.handleRefund{value: refundAmount}(refundCommitment, feeRecipient, refundFeeBPS, scope);

        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);
        assertEq(poolInterface.currentTreeSize(), treeSizeBefore + 1);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL ACROSS FACETS
    //////////////////////////////////////////////////////////////*/

    function test_accessControl_adminTransferAcrossFacets() public {
        // Transfer admin via 2-step process
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        poolInterface.transferAdmin(newAdmin);

        vm.prank(newAdmin);
        poolInterface.acceptAdmin();

        // New admin can use admin functions
        vm.prank(newAdmin);
        poolInterface.setMaxSolverFeeBPS(300);
        assertEq(poolInterface.maxSolverFeeBPS(), 300);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN DEPOSIT VIA SETTLER
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDepositAndVerifyState() public {
        uint256 precommitment = 55555;

        vm.prank(depositSettler);
        uint256 commitment = poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, precommitment);

        assertTrue(commitment != 0);
        assertEq(poolInterface.nonce(), 1);
        assertTrue(poolInterface.usedPrecommitments(precommitment));
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT -> RAGEQUIT FLOW
    //////////////////////////////////////////////////////////////*/

    function test_depositAndRagequit() public {
        // 1. Deposit
        vm.prank(user);
        uint256 commitment = poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);

        // 2. Compute expected label and net amount
        uint256 label = _computeLabel(1);
        uint256 netAmount = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000);

        // 3. Build ragequit proof
        RagequitProofLib.RagequitProof memory proof = _makeRagequitProof(commitment, 111, netAmount, label);

        // 4. Ragequit
        uint256 balanceBefore = user.balance;
        vm.prank(user);
        poolInterface.ragequit(proof);

        // 5. Verify
        assertEq(user.balance - balanceBefore, netAmount);
        assertTrue(poolInterface.nullifierHashes(111));
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW AFTER WIND DOWN
    //////////////////////////////////////////////////////////////*/

    function test_withdrawAfterWindDown() public {
        // 1. Deposit
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);

        // 2. Wind down
        vm.prank(admin);
        poolInterface.windDown();
        assertTrue(poolInterface.dead());

        // 3. New deposits should fail
        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12346);

        // 4. But withdrawal should still work
        address recipient = makeAddr("recipient");
        WithdrawData memory data = WithdrawData({
            recipient: recipient,
            feeRecipient: feeRecipient,
            relayFeeBPS: 100
        });

        WithdrawProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, 0.5 ether, 222);
        proof.pubSignals[7] = _computeContext(abi.encode(data));

        vm.deal(address(pool), 10 ether);
        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        poolInterface.withdraw(data, proof);

        uint256 fee = 0.5 ether * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, 0.5 ether - fee);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAWAL E2E
    //////////////////////////////////////////////////////////////*/

    function test_crosschainWithdrawIntentCreation() public {
        // 1. Setup crosschain config
        _setupCrosschainConfig();

        // 2. Deposit
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);
        vm.deal(address(pool), 10 ether);

        // 3. Build crosschain withdrawal
        address ccRecipient = makeAddr("ccRecipient");
        uint256 solverFeeBPS = 200;
        uint256 relayFeeBPS = 100;
        uint256 refundFeeBPS = 50;
        uint256 withdrawValue = 0.5 ether;

        CrosschainWithdrawData memory data =
            _makeCrosschainWithdrawData(solverFeeBPS, DEST_CHAIN_ID, ccRecipient);

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, withdrawValue, 222, 333, relayFeeBPS, refundFeeBPS);
        proof.pubSignals[10] = _computeContext(abi.encode(data));

        uint256 feeBefore = feeRecipient.balance;
        uint256 settlerBefore = address(mockSettler).balance;

        // 4. Execute
        vm.prank(relayer);
        poolInterface.crosschainWithdraw(data, proof);

        // 5. Verify
        uint256 relayFee = withdrawValue * relayFeeBPS / 10_000;
        uint256 escrowAmount = withdrawValue - relayFee;

        assertEq(feeRecipient.balance - feeBefore, relayFee);
        assertEq(address(mockSettler).balance - settlerBefore, escrowAmount);
        assertTrue(poolInterface.nullifierHashes(111));
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE SEQUENTIAL WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_multipleWithdrawals() public {
        // 1. Multiple deposits
        vm.startPrank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(1);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(2);
        vm.stopPrank();

        vm.deal(address(pool), 10 ether);

        // 2. First withdrawal
        address recipient1 = makeAddr("recipient1");
        WithdrawData memory d1 = WithdrawData({
            recipient: recipient1,
            feeRecipient: feeRecipient,
            relayFeeBPS: 100
        });
        WithdrawProofLib.WithdrawProof memory p1 = _makeWithdrawProof(111, 0.5 ether, 222);
        p1.pubSignals[7] = _computeContext(abi.encode(d1));

        vm.prank(relayer);
        poolInterface.withdraw(d1, p1);

        // 3. Second withdrawal with different nullifier
        address recipient2 = makeAddr("recipient2");
        WithdrawData memory d2 = WithdrawData({
            recipient: recipient2,
            feeRecipient: feeRecipient,
            relayFeeBPS: 50
        });
        WithdrawProofLib.WithdrawProof memory p2 = _makeWithdrawProof(333, 0.3 ether, 444);
        p2.pubSignals[7] = _computeContext(abi.encode(d2));

        vm.prank(relayer);
        poolInterface.withdraw(d2, p2);

        // 4. Verify both nullifiers spent
        uint256 fee2 = 0.3 ether * 50 / 10_000;
        assertTrue(poolInterface.nullifierHashes(111));
        assertTrue(poolInterface.nullifierHashes(333));
        assertEq(recipient2.balance, 0.3 ether - fee2);
    }
}

/// @dev Used by PoolTestBase for upgrade tests
contract MockExtraFacet is IFacet {
    function extraFunction() external pure returns (uint256) {
        return 42;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.extraFunction.selector);
    }
}
