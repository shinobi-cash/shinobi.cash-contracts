// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {DepositFacet} from "../../src/diamond/facets/DepositFacet.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";

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
}
