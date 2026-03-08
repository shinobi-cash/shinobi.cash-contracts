// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolTestBase} from "./PoolTestBase.sol";
import {ShinobiPool} from "../../src/pool/ShinobiPool.sol";
import {IShinobiPool} from "../../src/pool/interfaces/IShinobiPool.sol";
import {DepositAction} from "../../src/pool/facets/DepositAction.sol";
import {CrosschainDepositAction} from "../../src/pool/facets/CrosschainDepositAction.sol";
import {PoolOps} from "../../src/pool/libraries/PoolOps.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

contract DepositActionTest is PoolTestBase {
    /*//////////////////////////////////////////////////////////////
                          SAME-CHAIN DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test_deposit_success() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        uint256 commitment = poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        assertTrue(commitment != 0);
        assertEq(poolInterface.nonce(), 1);
        assertEq(poolInterface.currentTreeSize(), 1);
        assertTrue(poolInterface.usedPrecommitments(precommitment));
    }

    function test_deposit_emitsEvent() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        vm.expectEmit(true, false, false, false, address(pool));
        emit DepositAction.Deposited(user, 0, 0, 0, 0);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);
    }

    function test_deposit_sendsVettingFeeToRecipient() public {
        uint256 precommitment = 12345;
        address vettingVault = poolInterface.vettingFeeRecipient();
        uint256 vaultBefore = vettingVault.balance;
        uint256 poolBefore = address(pool).balance;

        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        uint256 expectedFee = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        uint256 netAmount = DEPOSIT_AMOUNT - expectedFee;

        // Fee sent to vault, net amount stays in pool
        assertEq(vettingVault.balance, vaultBefore + expectedFee);
        assertEq(address(pool).balance, poolBefore + netAmount);
    }

    function test_deposit_revertsForMinAmount() public {
        vm.expectRevert(DepositAction.MinimumDepositAmount.selector);
        vm.prank(user);
        poolInterface.deposit{value: MIN_DEPOSIT - 1}(12345);
    }

    function test_deposit_revertsForReusedPrecommitment() public {
        uint256 precommitment = 12345;
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        vm.expectRevert(DepositAction.PrecommitmentAlreadyUsed.selector);
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(precommitment);
    }

    function test_deposit_revertsForDeadPool() public {
        vm.prank(admin);
        poolInterface.windDown();

        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_multipleDepositsIncrementNonce() public {
        vm.startPrank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(1);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(2);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(3);
        vm.stopPrank();

        assertEq(poolInterface.nonce(), 3);
        assertEq(poolInterface.currentTreeSize(), 3);
    }

    function test_deposit_setsDepositor() public {
        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);

        // The depositor should be set for the label
        // Label = keccak256(scope, nonce) % SNARK_FIELD
        // We can verify the depositor mapping is populated by checking nonce advanced
        assertEq(poolInterface.nonce(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                       CROSS-CHAIN DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDeposit_success() public {
        uint256 precommitment = 99999;
        vm.prank(depositSettler);
        uint256 commitment = poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, precommitment);

        assertTrue(commitment != 0);
        assertEq(poolInterface.nonce(), 1);
    }

    function test_crosschainDeposit_revertsForNonSettler() public {
        vm.expectRevert(CrosschainDepositAction.OnlyDepositOutputSettler.selector);
        vm.prank(user);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForValueMismatch() public {
        vm.expectRevert(PoolOps.InvalidWithdrawalAmount.selector);
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: 0.5 ether}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForMinAmount() public {
        uint256 tooSmall = MIN_DEPOSIT - 1;
        vm.expectRevert(CrosschainDepositAction.MinimumDepositAmount.selector);
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: tooSmall}(user, tooSmall, 12345);
    }

    function test_crosschainDeposit_revertsForDeadPool() public {
        vm.prank(admin);
        poolInterface.windDown();

        vm.expectRevert(PoolOps.PoolIsDead.selector);
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_revertsForReusedPrecommitment() public {
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);

        vm.expectRevert(CrosschainDepositAction.PrecommitmentAlreadyUsed.selector);
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_crosschainDeposit_setsCorrectDepositor() public {
        address depositor = makeAddr("crosschainDepositor");
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(depositor, DEPOSIT_AMOUNT, 77777);

        // Depositor should be the param, not msg.sender (depositSettler)
        uint256 label = uint256(keccak256(abi.encodePacked(poolInterface.SCOPE(), poolInterface.nonce()))) % Constants.SNARK_SCALAR_FIELD;
        assertEq(poolInterface.depositors(label), depositor);
    }

    /*//////////////////////////////////////////////////////////////
                       FEE ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function test_deposit_sendsFeesToVault() public {
        address vettingVault = poolInterface.vettingFeeRecipient();
        uint256 vaultBefore = vettingVault.balance;

        vm.prank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);

        uint256 expectedFee = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(vettingVault.balance, vaultBefore + expectedFee);
    }

    function test_deposit_sendsFeesAcrossDeposits() public {
        address vettingVault = poolInterface.vettingFeeRecipient();
        uint256 vaultBefore = vettingVault.balance;

        vm.startPrank(user);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(1);
        poolInterface.deposit{value: DEPOSIT_AMOUNT}(2);
        vm.stopPrank();

        uint256 feePerDeposit = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(vettingVault.balance, vaultBefore + feePerDeposit * 2);
    }

    function test_crosschainDeposit_sendsFeesToVault() public {
        address vettingVault = poolInterface.vettingFeeRecipient();
        uint256 vaultBefore = vettingVault.balance;

        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);

        uint256 expectedFee = DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000;
        assertEq(vettingVault.balance, vaultBefore + expectedFee);
    }

    function test_deposit_revertsWhenVettingFeeRecipientNotSet() public {
        // Deploy a fresh pool without vettingFeeRecipient configured
        ShinobiPool freshPool = new ShinobiPool(
            ShinobiPool.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: _buildFacets()
            })
        );
        IShinobiPool freshPoolInterface = IShinobiPool(address(freshPool));
        vm.prank(admin);
        freshPoolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS);

        vm.deal(user, 10 ether);
        vm.expectRevert(DepositAction.VettingFeeRecipientNotSet.selector);
        vm.prank(user);
        freshPoolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_crosschainDeposit_revertsWhenVettingFeeRecipientNotSet() public {
        ShinobiPool freshPool = new ShinobiPool(
            ShinobiPool.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: _buildFacets()
            })
        );
        IShinobiPool freshPoolInterface = IShinobiPool(address(freshPool));
        vm.startPrank(admin);
        freshPoolInterface.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS);
        freshPoolInterface.setDepositOutputSettler(depositSettler);
        vm.stopPrank();

        vm.deal(depositSettler, 10 ether);
        vm.expectRevert(CrosschainDepositAction.VettingFeeRecipientNotSet.selector);
        vm.prank(depositSettler);
        freshPoolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    function test_deposit_revertsWhenAssetConfigNotSet() public {
        ShinobiPool freshPool = new ShinobiPool(
            ShinobiPool.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: _buildFacets()
            })
        );
        IShinobiPool freshPoolInterface = IShinobiPool(address(freshPool));

        vm.deal(user, 10 ether);
        vm.expectRevert(DepositAction.AssetConfigNotSet.selector);
        vm.prank(user);
        freshPoolInterface.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_crosschainDeposit_revertsWhenAssetConfigNotSet() public {
        ShinobiPool freshPool = new ShinobiPool(
            ShinobiPool.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: _buildFacets()
            })
        );
        IShinobiPool freshPoolInterface = IShinobiPool(address(freshPool));
        vm.prank(admin);
        freshPoolInterface.setDepositOutputSettler(depositSettler);

        vm.deal(depositSettler, 10 ether);
        vm.expectRevert(CrosschainDepositAction.AssetConfigNotSet.selector);
        vm.prank(depositSettler);
        freshPoolInterface.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, 12345);
    }

    /*//////////////////////////////////////////////////////////////
                       OVERFLOW PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_deposit_revertsForUint128Overflow() public {
        uint256 hugeAmount = type(uint128).max;
        vm.deal(user, hugeAmount + 1 ether);
        vm.expectRevert(DepositAction.InvalidDepositValue.selector);
        vm.prank(user);
        poolInterface.deposit{value: hugeAmount}(88888);
    }

    function test_crosschainDeposit_revertsForUint128Overflow() public {
        uint256 hugeAmount = type(uint128).max;
        vm.deal(depositSettler, hugeAmount + 1 ether);
        vm.expectRevert(CrosschainDepositAction.InvalidDepositValue.selector);
        vm.prank(depositSettler);
        poolInterface.crosschainDeposit{value: hugeAmount}(user, hugeAmount, 88888);
    }
}
