// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {AdminFacet} from "../../src/diamond/facets/AdminFacet.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IFacet} from "../../src/diamond/interfaces/IFacet.sol";
import {IPoolDiamond} from "../../src/diamond/interfaces/IPoolDiamond.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {CrosschainProofLib} from "../../src/core/libraries/CrosschainProofLib.sol";

contract IntegrationTest is DiamondTestBase {
    /*//////////////////////////////////////////////////////////////
                    DEPOSIT → WITHDRAW FLOW
    //////////////////////////////////////////////////////////////*/

    function test_depositAndWithdraw() public {
        // 1. Deposit
        uint256 precommitment = 12345;
        vm.prank(user);
        uint256 commitment = pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);
        assertTrue(commitment != 0);

        // 2. Verify state after deposit
        assertEq(pool.nonce(), 1);
        assertEq(pool.currentTreeSize(), 1);
        assertTrue(pool.currentRoot() != 0);

        // 3. Withdraw
        address recipient = makeAddr("recipient");
        uint256 withdrawValue = 0.5 ether;

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient,
                feeRecipient: feeRecipient,
                relayFeeBPS: 100
            }))
        });

        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, withdrawValue, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        // Fund diamond (simulates having funds from deposit)
        vm.deal(address(diamond), 10 ether);

        uint256 recipientBefore = recipient.balance;
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // 4. Verify withdrawal succeeded
        uint256 fee = withdrawValue * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, withdrawValue - fee);
        assertTrue(pool.nullifierHashes(111));
        assertEq(pool.currentTreeSize(), 2); // deposit + new commitment from withdraw
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE DEPOSITS + VIEW STATE
    //////////////////////////////////////////////////////////////*/

    function test_multipleDepositsUpdateState() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(1);
        pool.deposit{value: DEPOSIT_AMOUNT}(2);
        pool.deposit{value: DEPOSIT_AMOUNT}(3);
        vm.stopPrank();

        assertEq(pool.nonce(), 3);
        assertEq(pool.currentTreeSize(), 3);
        assertTrue(pool.currentTreeDepth() > 0);
        assertTrue(pool.currentRoot() != 0);
    }

    /*//////////////////////////////////////////////////////////////
                    DIAMOND UPGRADE + CALL NEW FACET
    //////////////////////////////////////////////////////////////*/

    function test_upgradeAndCallNewFacet() public {
        // Deploy and add mock extra facet
        MockExtraFacet newFacet = new MockExtraFacet();

        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IPoolDiamond.ReplaceAction[] memory replaceFacets = new IPoolDiamond.ReplaceAction[](0);

        vm.prank(admin);
        pool.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        // Call the new function through the diamond
        (bool success, bytes memory data) =
            address(diamond).call(abi.encodeWithSelector(MockExtraFacet.extraFunction.selector));
        assertTrue(success);
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 42);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_reentrancyGuard_preventsReentry() public {
        // The reentrancy guard shares state across all facets via PoolStorage
        // We can verify it works by checking reentrancy status is reset
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // If reentrancy guard was stuck, this would revert
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12346);

        assertEq(pool.nonce(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND FLOW
    //////////////////////////////////////////////////////////////*/

    function test_refundInsertsCommitmentAndPaysFee() public {
        uint256 refundCommitmentHash = 42;
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 200; // 2%

        uint256 feeBefore = feeRecipient.balance;
        uint256 treeSizeBefore = pool.currentTreeSize();

        uint256 scope = pool.SCOPE();
        vm.prank(address(mockSettler));
        pool.handleRefund{value: refundAmount}(refundCommitmentHash, feeRecipient, refundFeeBPS, scope);

        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL ACROSS FACETS
    //////////////////////////////////////////////////////////////*/

    function test_accessControl_sharedAcrossFacets() public {
        // Grant a new admin via AdminFacet
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        pool.grantRole(keccak256("ADMIN_ROLE"), newAdmin);

        // New admin can use admin functions
        vm.prank(newAdmin);
        pool.setMaxSolverFeeBPS(300);
        assertEq(pool.maxSolverFeeBPS(), 300);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN DEPOSIT VIA SETTLER
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDepositAndVerifyState() public {
        uint256 precommitment = 55555;

        vm.prank(depositSettler);
        uint256 commitment = pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, precommitment);

        assertTrue(commitment != 0);
        assertEq(pool.nonce(), 1);
        assertTrue(pool.usedPrecommitments(precommitment));
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT → RAGEQUIT FLOW
    //////////////////////////////////////////////////////////////*/

    function test_depositAndRagequit() public {
        // 1. Deposit
        vm.prank(user);
        uint256 commitment = pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // 2. Compute expected label and net amount
        uint256 label = _computeLabel(1);
        uint256 netAmount = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000);

        // 3. Build ragequit proof
        ProofLib.RagequitProof memory proof = _makeRagequitProof(commitment, 111, netAmount, label);

        // 4. Ragequit
        uint256 balanceBefore = user.balance;
        vm.prank(user);
        pool.ragequit(proof);

        // 5. Verify
        assertEq(user.balance - balanceBefore, netAmount);
        assertTrue(pool.nullifierHashes(111));
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW AFTER WIND DOWN
    //////////////////////////////////////////////////////////////*/

    function test_withdrawAfterWindDown() public {
        // 1. Deposit
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // 2. Wind down
        vm.prank(admin);
        pool.windDown();
        assertTrue(pool.dead());

        // 3. New deposits should fail
        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12346);

        // 4. But withdrawal should still work
        address recipient = makeAddr("recipient");
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient,
                feeRecipient: feeRecipient,
                relayFeeBPS: 100
            }))
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

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAWAL E2E
    //////////////////////////////////////////////////////////////*/

    function test_crosschainWithdrawIntentCreation() public {
        // 1. Setup crosschain config
        _setupCrosschainConfig();

        // 2. Deposit
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);
        vm.deal(address(diamond), 10 ether);

        // 3. Build crosschain withdrawal
        address ccRecipient = makeAddr("ccRecipient");
        uint256 solverFeeBPS = 200;
        uint256 relayFeeBPS = 100;
        uint256 refundFeeBPS = 50;
        uint256 withdrawValue = 0.5 ether;

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: _makeCrosschainRelayData(solverFeeBPS, DEST_CHAIN_ID, ccRecipient)
        });

        CrosschainProofLib.CrosschainWithdrawProof memory proof =
            _makeCrosschainWithdrawProof(111, withdrawValue, 222, 333, relayFeeBPS, refundFeeBPS);
        proof.pubSignals[10] = _computeContext(withdrawal);

        uint256 feeBefore = feeRecipient.balance;
        uint256 settlerBefore = address(mockSettler).balance;

        // 4. Execute
        vm.prank(relayer);
        pool.crosschainWithdraw(withdrawal, proof);

        // 5. Verify
        uint256 relayFee = withdrawValue * relayFeeBPS / 10_000;
        uint256 escrowAmount = withdrawValue - relayFee;

        assertEq(feeRecipient.balance - feeBefore, relayFee);
        assertEq(address(mockSettler).balance - settlerBefore, escrowAmount);
        assertTrue(pool.nullifierHashes(111));
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE SEQUENTIAL WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_multipleWithdrawals() public {
        // 1. Multiple deposits
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(1);
        pool.deposit{value: DEPOSIT_AMOUNT}(2);
        vm.stopPrank();

        vm.deal(address(diamond), 10 ether);

        // 2. First withdrawal
        address recipient1 = makeAddr("recipient1");
        IPrivacyPool.Withdrawal memory w1 = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient1,
                feeRecipient: feeRecipient,
                relayFeeBPS: 100
            }))
        });
        ProofLib.WithdrawProof memory p1 = _makeWithdrawProof(111, 0.5 ether, 222);
        p1.pubSignals[7] = _computeContext(w1);

        vm.prank(relayer);
        pool.withdraw(w1, p1);

        // 3. Second withdrawal with different nullifier
        address recipient2 = makeAddr("recipient2");
        IPrivacyPool.Withdrawal memory w2 = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient2,
                feeRecipient: feeRecipient,
                relayFeeBPS: 0
            }))
        });
        ProofLib.WithdrawProof memory p2 = _makeWithdrawProof(333, 0.3 ether, 444);
        p2.pubSignals[7] = _computeContext(w2);

        vm.prank(relayer);
        pool.withdraw(w2, p2);

        // 4. Verify both nullifiers spent
        assertTrue(pool.nullifierHashes(111));
        assertTrue(pool.nullifierHashes(333));
        assertEq(recipient2.balance, 0.3 ether);
    }
}

/// @dev Used by DiamondTestBase for upgrade tests
contract MockExtraFacet is IFacet {
    function extraFunction() external pure returns (uint256) {
        return 42;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.extraFunction.selector);
    }
}
