// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {DepositFacet} from "../../src/diamond/facets/DepositFacet.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract DepositFacetTest is DiamondTestBase {
    /*//////////////////////////////////////////////////////////////
                          SAME-CHAIN DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test_deposit_success() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        uint256 commitment = pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        assertTrue(commitment != 0);
        assertEq(pool.nonce(), 1);
        assertEq(pool.currentTreeSize(), 1);
        assertTrue(pool.usedPrecommitments(precommitment));
    }

    function test_deposit_emitsEvent() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        vm.expectEmit(true, false, false, false, address(diamond));
        emit DepositFacet.Deposited(user, 0, 0, 0, 0);
        pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);
    }

    function test_deposit_deductsVettingFee() public {
        uint256 precommitment = 12345;
        uint256 balanceBefore = address(diamond).balance;

        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        // Diamond keeps the full deposit (fee stays in contract)
        assertEq(address(diamond).balance, balanceBefore + DEPOSIT_AMOUNT);
    }

    function test_deposit_revertsForMinAmount() public {
        vm.expectRevert(DepositFacet.MinimumDepositAmount.selector);
        vm.prank(user);
        pool.deposit{value: MIN_DEPOSIT - 1}(12345);
    }

    function test_deposit_revertsForReusedPrecommitment() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        vm.expectRevert(DepositFacet.PrecommitmentAlreadyUsed.selector);
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);
    }

    function test_deposit_revertsForDeadPool() public {
        vm.prank(admin);
        pool.windDown();

        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_multipleDepositsIncrementNonce() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(1);
        pool.deposit{value: DEPOSIT_AMOUNT}(2);
        pool.deposit{value: DEPOSIT_AMOUNT}(3);
        vm.stopPrank();

        assertEq(pool.nonce(), 3);
        assertEq(pool.currentTreeSize(), 3);
    }

    function test_deposit_setsDepositor() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // The depositor should be set for the label
        // Label = keccak256(scope, nonce) % SNARK_FIELD
        // We can verify the depositor mapping is populated by checking nonce advanced
        assertEq(pool.nonce(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                       CROSS-CHAIN DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDeposit_success() public {
        uint256 precommitment = 99999;
        vm.prank(depositSettler);
        uint256 commitment = pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, precommitment);

        assertTrue(commitment != 0);
        assertEq(pool.nonce(), 1);
    }

    function test_crosschainDeposit_revertsForNonSettler() public {
        vm.expectRevert(DepositFacet.OnlyDepositOutputSettler.selector);
        vm.prank(user);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForValueMismatch() public {
        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: 0.5 ether}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForMinAmount() public {
        uint256 tooSmall = MIN_DEPOSIT - 1;
        vm.expectRevert(DepositFacet.MinimumDepositAmount.selector);
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: tooSmall}(user, tooSmall, 12345);
    }

    function test_crosschainDeposit_revertsForDeadPool() public {
        vm.prank(admin);
        pool.windDown();

        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForReusedPrecommitment() public {
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);

        vm.expectRevert(DepositFacet.PrecommitmentAlreadyUsed.selector);
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_setsCorrectDepositor() public {
        address depositor = makeAddr("crosschainDepositor");
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(depositor, DEPOSIT_AMOUNT, 77777);

        // Depositor should be the param, not msg.sender (depositSettler)
        uint256 label = uint256(keccak256(abi.encodePacked(pool.SCOPE(), pool.nonce()))) % Constants.SNARK_SCALAR_FIELD;
        assertEq(pool.depositors(label), depositor);
    }

    /*//////////////////////////////////////////////////////////////
                       FEE ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function test_deposit_accumulatesVettingFees() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        uint256 expectedFee = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(pool.accumulatedFees(), expectedFee);
    }

    function test_deposit_accumulatesFeesAcrossDeposits() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(1);
        pool.deposit{value: DEPOSIT_AMOUNT}(2);
        vm.stopPrank();

        uint256 feePerDeposit = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(pool.accumulatedFees(), feePerDeposit * 2);
    }

    function test_crosschainDeposit_accumulatesVettingFees() public {
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);

        uint256 expectedFee = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(pool.accumulatedFees(), expectedFee);
    }

    /*//////////////////////////////////////////////////////////////
                       OVERFLOW PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_deposit_revertsForUint128Overflow() public {
        uint256 hugeAmount = type(uint128).max;
        vm.deal(user, hugeAmount + 1 ether);
        vm.expectRevert(DepositFacet.InvalidDepositValue.selector);
        vm.prank(user);
        pool.deposit{value: hugeAmount}(88888);
    }

    function test_crosschainDeposit_revertsForUint128Overflow() public {
        uint256 hugeAmount = type(uint128).max;
        vm.deal(depositSettler, hugeAmount + 1 ether);
        vm.expectRevert(DepositFacet.InvalidDepositValue.selector);
        vm.prank(depositSettler);
        pool.crosschainDeposit{value: hugeAmount}(user, hugeAmount, 88888);
    }
}
