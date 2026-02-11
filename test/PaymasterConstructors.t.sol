// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/SimpleShinobiCashPoolPaymaster.sol";
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/CrossChainWithdrawalPaymaster.sol";
import {Withdraw2Paymaster} from "../src/paymaster/Withdraw2Paymaster.sol";
import {CrossChainWithdraw2Paymaster} from "../src/paymaster/CrossChainWithdraw2Paymaster.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrossChainWithdraw2Verifier} from "../src/core/interfaces/ICrossChainWithdraw2Verifier.sol";
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
    address public crossChainWithdraw2Verifier = makeAddr("crossChainWithdraw2Verifier");
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

    function test_SimpleShinobiCashPoolPaymaster_constructor_success() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
    }

    function test_SimpleShinobiCashPoolPaymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(SimpleShinobiCashPoolPaymaster.InvalidAddress.selector);
        new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IPrivacyPool(ethPool)
        );
    }

    function test_SimpleShinobiCashPoolPaymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(SimpleShinobiCashPoolPaymaster.InvalidAddress.selector);
        new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(address(0))
        );
    }

    function test_SimpleShinobiCashPoolPaymaster_setExpectedSmartAccount_success() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_SimpleShinobiCashPoolPaymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectRevert(SimpleShinobiCashPoolPaymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_SimpleShinobiCashPoolPaymaster_setExpectedSmartAccount_onlyOwner() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_SimpleShinobiCashPoolPaymaster_receive_acceptsETH() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_SimpleShinobiCashPoolPaymaster_constants() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(paymaster.POST_OP_GAS_LIMIT(), 100_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 550_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 400_000);
    }

    /*//////////////////////////////////////////////////////////////
                CROSS CHAIN WITHDRAWAL PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CrossChainWithdrawalPaymaster_constructor_success() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_POOL()), ethPool);
    }

    function test_CrossChainWithdrawalPaymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(CrossChainWithdrawalPaymaster.InvalidAddress.selector);
        new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            ShinobiCashPool(ethPool)
        );
    }

    function test_CrossChainWithdrawalPaymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(CrossChainWithdrawalPaymaster.InvalidAddress.selector);
        new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(address(0))
        );
    }

    function test_CrossChainWithdrawalPaymaster_setExpectedSmartAccount_success() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_CrossChainWithdrawalPaymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectRevert(CrossChainWithdrawalPaymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_CrossChainWithdrawalPaymaster_setExpectedSmartAccount_onlyOwner() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_CrossChainWithdrawalPaymaster_receive_acceptsETH() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_CrossChainWithdrawalPaymaster_constants() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(paymaster.POST_OP_GAS_LIMIT(), 100_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 687_500);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 500_000);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw2Paymaster_constructor_success() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
        assertEq(address(paymaster.WITHDRAW2_VERIFIER()), withdraw2Verifier);
    }

    function test_Withdraw2Paymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(Withdraw2Paymaster.InvalidAddress.selector);
        new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );
    }

    function test_Withdraw2Paymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(Withdraw2Paymaster.InvalidAddress.selector);
        new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(address(0)),
            IWithdraw2Verifier(withdraw2Verifier)
        );
    }

    function test_Withdraw2Paymaster_constructor_revertsZeroVerifier() public {
        vm.expectRevert(Withdraw2Paymaster.InvalidAddress.selector);
        new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(address(0))
        );
    }

    function test_Withdraw2Paymaster_setExpectedSmartAccount_success() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
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

    function test_Withdraw2Paymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.expectRevert(Withdraw2Paymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_Withdraw2Paymaster_setExpectedSmartAccount_onlyOwner() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_Withdraw2Paymaster_receive_acceptsETH() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
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

    function test_Withdraw2Paymaster_constants() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(paymaster.POST_OP_GAS_LIMIT(), 100_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 650_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 500_000);
    }

    /*//////////////////////////////////////////////////////////////
                CROSS CHAIN WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CrossChainWithdraw2Paymaster_constructor_success() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        assertEq(address(paymaster.SHINOBI_CASH_ENTRYPOINT()), shinobiCashEntrypoint);
        assertEq(address(paymaster.ETH_CASH_POOL()), ethPool);
        assertEq(address(paymaster.CROSSCHAIN_WITHDRAW2_VERIFIER()), crossChainWithdraw2Verifier);
    }

    function test_CrossChainWithdraw2Paymaster_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(CrossChainWithdraw2Paymaster.InvalidAddress.selector);
        new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(0)),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );
    }

    function test_CrossChainWithdraw2Paymaster_constructor_revertsZeroPool() public {
        vm.expectRevert(CrossChainWithdraw2Paymaster.InvalidAddress.selector);
        new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(address(0)),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );
    }

    function test_CrossChainWithdraw2Paymaster_constructor_revertsZeroVerifier() public {
        vm.expectRevert(CrossChainWithdraw2Paymaster.InvalidAddress.selector);
        new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(address(0))
        );
    }

    function test_CrossChainWithdraw2Paymaster_setExpectedSmartAccount_success() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        vm.expectEmit(true, true, false, false);
        emit ExpectedSmartAccountUpdated(address(0), smartAccount);

        paymaster.setExpectedSmartAccount(smartAccount);

        assertEq(paymaster.expectedSmartAccount(), smartAccount);
    }

    function test_CrossChainWithdraw2Paymaster_setExpectedSmartAccount_revertsZeroAddress() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        vm.expectRevert(CrossChainWithdraw2Paymaster.InvalidProcessooor.selector);
        paymaster.setExpectedSmartAccount(address(0));
    }

    function test_CrossChainWithdraw2Paymaster_setExpectedSmartAccount_onlyOwner() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        vm.expectRevert();
        vm.prank(user);
        paymaster.setExpectedSmartAccount(smartAccount);
    }

    function test_CrossChainWithdraw2Paymaster_receive_acceptsETH() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_CrossChainWithdraw2Paymaster_constants() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        assertEq(paymaster.POST_OP_GAS_LIMIT(), 100_000);
        assertEq(paymaster.MIN_CALL_GAS_LIMIT(), 750_000);
        assertEq(paymaster.MIN_PAYMASTER_VERIFICATION_GAS(), 550_000);
    }

    /*//////////////////////////////////////////////////////////////
                        CAN UPDATE SMART ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SimpleShinobiCashPoolPaymaster_setExpectedSmartAccount_canUpdate() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
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

    function test_CrossChainWithdrawalPaymaster_setExpectedSmartAccount_canUpdate() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
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

    function test_Withdraw2Paymaster_setExpectedSmartAccount_canUpdate() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
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

    function test_CrossChainWithdraw2Paymaster_setExpectedSmartAccount_canUpdate() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
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

    function test_SimpleShinobiCashPoolPaymaster_expectedSmartAccount_initiallyZero() public {
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_CrossChainWithdrawalPaymaster_expectedSmartAccount_initiallyZero() public {
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_Withdraw2Paymaster_expectedSmartAccount_initiallyZero() public {
        Withdraw2Paymaster paymaster = new Withdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }

    function test_CrossChainWithdraw2Paymaster_expectedSmartAccount_initiallyZero() public {
        CrossChainWithdraw2Paymaster paymaster = new CrossChainWithdraw2Paymaster(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        assertEq(paymaster.expectedSmartAccount(), address(0));
    }
}
