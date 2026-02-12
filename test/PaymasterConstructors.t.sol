// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ShinobiNativeWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeWithdrawalPaymaster.sol";
import {ShinobiNativeCrosschainWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdrawalPaymaster.sol";
import {ShinobiNativeWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeWithdraw2Paymaster.sol";
import {ShinobiNativeCrosschainWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdraw2Paymaster.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {ShinobiCashPool} from "../src/core/ShinobiCashPool.sol";

/**
 * @notice Mock ERC-4337 EntryPoint that satisfies interface check
 */
contract MockEntryPoint {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract PaymasterConstructorsTest is Test {
    // Mock addresses
    MockEntryPoint public mockEntryPoint;
    address public shinobiCashEntrypoint = makeAddr("shinobiCashEntrypoint");
    address public ethPool = makeAddr("ethPool");
    address public withdraw2Verifier = makeAddr("withdraw2Verifier");
    address public crosschainWithdraw2Verifier = makeAddr("crosschainWithdraw2Verifier");
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public smartAccount = makeAddr("smartAccount");

    // Events
    event ExpectedSmartAccountUpdated(
        address indexed previousAccount,
        address indexed newAccount
    );

    function setUp() public {
        mockEntryPoint = new MockEntryPoint();
        vm.deal(owner, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                SIMPLE SHINOBI CASH POOL PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeWithdrawalPaymaster_constructor_success() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
    }

    function test_ShinobiNativeWithdrawalPaymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiNativeWithdrawalPaymaster.InvalidAddress.selector);
        new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IPrivacyPool(ethPool)
        );
    }

    function test_ShinobiNativeWithdrawalPaymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(ShinobiNativeWithdrawalPaymaster.InvalidAddress.selector);
        new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(address(0))
        );
    }

    function test_ShinobiNativeWithdrawalPaymaster_setExpectedSmartAccount_success() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_ShinobiNativeWithdrawalPaymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectRevert(ShinobiNativeWithdrawalPaymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_ShinobiNativeWithdrawalPaymaster_setExpectedSmartAccount_onlyOwner() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_ShinobiNativeWithdrawalPaymaster_receive_acceptsETH() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_ShinobiNativeWithdrawalPaymaster_constants() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(paymaster.MIN_POST_OP_GAS_LIMIT(), 80_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 550_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 400_000);
    }

    /*//////////////////////////////////////////////////////////////
                CROSS CHAIN WITHDRAWAL PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_constructor_success() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_POOL()), ethPool);
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.InvalidAddress.selector);
        new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            ShinobiCashPool(ethPool)
        );
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.InvalidAddress.selector);
        new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(address(0))
        );
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_setExpectedSmartAccount_success() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_setExpectedSmartAccount_onlyOwner() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_receive_acceptsETH() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_constants() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(paymaster.MIN_POST_OP_GAS_LIMIT(), 50_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 687_500);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 500_000);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeWithdraw2Paymaster_constructor_success() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
        assertEq(address(paymaster.WITHDRAW2_VERIFIER()), withdraw2Verifier);
    }

    function test_ShinobiNativeWithdraw2Paymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );
    }

    function test_ShinobiNativeWithdraw2Paymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(address(0)),
            IWithdraw2Verifier(withdraw2Verifier)
        );
    }

    function test_ShinobiNativeWithdraw2Paymaster_constructor_revertsZeroVerifier() public {
        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(address(0))
        );
    }

    function test_ShinobiNativeWithdraw2Paymaster_setExpectedSmartAccount_success() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_ShinobiNativeWithdraw2Paymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_ShinobiNativeWithdraw2Paymaster_setExpectedSmartAccount_onlyOwner() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_ShinobiNativeWithdraw2Paymaster_receive_acceptsETH() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_ShinobiNativeWithdraw2Paymaster_constants() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(paymaster.MIN_POST_OP_GAS_LIMIT(), 80_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 650_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 500_000);
    }

    /*//////////////////////////////////////////////////////////////
                CROSS CHAIN WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_constructor_success() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
        assertEq(address(paymaster.CROSSCHAIN_WITHDRAW2_VERIFIER()), crosschainWithdraw2Verifier);
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(address(0)),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_constructor_revertsZeroVerifier() public {
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.InvalidAddress.selector);
        new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(address(0))
        );
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_setExpectedSmartAccount_success() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_setExpectedSmartAccount_onlyOwner() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_receive_acceptsETH() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_constants() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        assertEq(paymaster.MIN_POST_OP_GAS_LIMIT(), 50_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 750_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 550_000);
    }

    /*//////////////////////////////////////////////////////////////
                        CAN UPDATE SMART ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeWithdrawalPaymaster_setExpectedSmartAccount_canUpdate() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        paymaster.setExpectedSmartAccount(smartAccount);

        address newSmartAccount = makeAddr("newSmartAccount");

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(smartAccount, newSmartAccount);

        paymaster.setExpectedSmartAccount(newSmartAccount);

        assertEq(paymaster.expectedSmartAccount(), newSmartAccount);
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_setExpectedSmartAccount_canUpdate() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        paymaster.setExpectedSmartAccount(smartAccount);

        address newSmartAccount = makeAddr("newSmartAccount");

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(smartAccount, newSmartAccount);

        paymaster.setExpectedSmartAccount(newSmartAccount);

        assertEq(paymaster.expectedSmartAccount(), newSmartAccount);
    }

    function test_ShinobiNativeWithdraw2Paymaster_setExpectedSmartAccount_canUpdate() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        paymaster.setExpectedSmartAccount(smartAccount);

        address newSmartAccount = makeAddr("newSmartAccount");

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(smartAccount, newSmartAccount);

        paymaster.setExpectedSmartAccount(newSmartAccount);

        assertEq(paymaster.expectedSmartAccount(), newSmartAccount);
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_setExpectedSmartAccount_canUpdate() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        paymaster.setExpectedSmartAccount(smartAccount);

        address newSmartAccount = makeAddr("newSmartAccount");

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(smartAccount, newSmartAccount);

        paymaster.setExpectedSmartAccount(newSmartAccount);

        assertEq(paymaster.expectedSmartAccount(), newSmartAccount);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeWithdrawalPaymaster_expectedSmartAccount_initiallyZero() public {
        ShinobiNativeWithdrawalPaymaster paymaster = new ShinobiNativeWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_ShinobiNativeCrosschainWithdrawalPaymaster_expectedSmartAccount_initiallyZero() public {
        ShinobiNativeCrosschainWithdrawalPaymaster paymaster = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_ShinobiNativeWithdraw2Paymaster_expectedSmartAccount_initiallyZero() public {
        ShinobiNativeWithdraw2Paymaster paymaster = new ShinobiNativeWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_expectedSmartAccount_initiallyZero() public {
        ShinobiNativeCrosschainWithdraw2Paymaster paymaster = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }
}
