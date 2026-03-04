// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase, MockVerifier} from "./DiamondTestBase.sol";
import {AccessControlOps} from "../../src/diamond/libraries/AccessControlOps.sol";
import {AccessControlStorageLib} from "../../src/diamond/storage/AccessControlStorage.sol";
import {AdminFacet} from "../../src/diamond/facets/AdminFacet.sol";
import {IFacet} from "../../src/diamond/interfaces/IFacet.sol";
import {IPoolDiamond} from "../../src/diamond/interfaces/IPoolDiamond.sol";

contract AdminFacetTest is DiamondTestBase {
    /*//////////////////////////////////////////////////////////////
                          ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_grantRole_byAdmin() public {
        address newPostman = makeAddr("newPostman");
        vm.prank(admin);
        pool.grantRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman);
        assertTrue(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman));
    }

    function test_grantRole_revertsForUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ADMIN_ROLE
            )
        );
        vm.prank(user);
        pool.grantRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, user);
    }

    function test_revokeRole_byAdmin() public {
        vm.prank(admin);
        pool.revokeRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman);
        assertFalse(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman));
    }

    function test_renounceRole() public {
        vm.prank(aspPostman);
        pool.renounceRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman);
        assertFalse(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman));
    }

    function test_renounceRole_revertsForOtherAccount() public {
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlOps.AccessControlCannotRenounceOther.selector, aspPostman)
        );
        vm.prank(admin);
        pool.renounceRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman);
    }

    /*//////////////////////////////////////////////////////////////
                          ASSET CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_setAssetConfig() public {
        vm.prank(admin);
        pool.setAssetConfig(0.1 ether, 200, 1000);

        (uint256 minDeposit, uint256 vettingFee, uint256 maxRelay) = pool.assetConfig();
        assertEq(minDeposit, 0.1 ether);
        assertEq(vettingFee, 200);
        assertEq(maxRelay, 1000);
    }

    function test_setAssetConfig_revertsForInvalidBPS() public {
        vm.expectRevert(AdminFacet.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setAssetConfig(0, 10_001, 0);
    }

    function test_setAssetConfig_revertsForUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ADMIN_ROLE
            )
        );
        vm.prank(user);
        pool.setAssetConfig(0, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          SETTLERS
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalInputSettler() public {
        address newSettler = makeAddr("newSettler");
        vm.prank(admin);
        pool.setWithdrawalInputSettler(newSettler);
        assertEq(pool.withdrawalInputSettler(), newSettler);
    }

    function test_setWithdrawalInputSettler_revertsForZeroAddress() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalInputSettler(address(0));
    }

    function test_setDepositOutputSettler() public {
        address newSettler = makeAddr("newSettler");
        vm.prank(admin);
        pool.setDepositOutputSettler(newSettler);
        assertEq(pool.depositOutputSettler(), newSettler);
    }

    /*//////////////////////////////////////////////////////////////
                          MAX SOLVER FEE
    //////////////////////////////////////////////////////////////*/

    function test_setMaxSolverFeeBPS() public {
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(500);
        assertEq(pool.maxSolverFeeBPS(), 500);
    }

    function test_setMaxSolverFeeBPS_revertsForInvalidBPS() public {
        vm.expectRevert(AdminFacet.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(10_001);
    }

    /*//////////////////////////////////////////////////////////////
                          CHAIN CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalChainConfig() public {
        address outputSettler = makeAddr("outputSettler");
        address outputOracle = makeAddr("outputOracle");
        address fillOracle = makeAddr("fillOracle");

        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, outputSettler, outputOracle, fillOracle, 3600, 7200);

        (bool isConfigured, uint32 fillDeadline, uint32 expiry, address ws, address wo, address fo) =
            pool.withdrawalChainConfig(84532);
        assertTrue(isConfigured);
        assertEq(fillDeadline, 3600);
        assertEq(expiry, 7200);
        assertEq(ws, outputSettler);
        assertEq(wo, outputOracle);
        assertEq(fo, fillOracle);
    }

    function test_setWithdrawalChainConfig_revertsForZeroChainId() public {
        vm.expectRevert(AdminFacet.InvalidChainId.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(0, address(1), address(1), address(1), 3600, 7200);
    }

    /*//////////////////////////////////////////////////////////////
                          ASP ROOT
    //////////////////////////////////////////////////////////////*/

    function test_updateRoot() public {
        vm.prank(aspPostman);
        uint256 index = pool.updateRoot(123, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");

        assertEq(pool.latestRoot(), 123);
        (uint256 root, string memory cid, uint256 ts) = pool.associationSets(index);
        assertEq(root, 123);
        assertEq(cid, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
        assertEq(ts, block.timestamp);
    }

    function test_updateRoot_revertsForEmptyRoot() public {
        vm.expectRevert(AdminFacet.EmptyRoot.selector);
        vm.prank(aspPostman);
        pool.updateRoot(0, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
    }

    function test_updateRoot_revertsForEmptyCID() public {
        vm.expectRevert(AdminFacet.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, "");
    }

    function test_updateRoot_revertsForUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ASP_POSTMAN_ROLE
            )
        );
        vm.prank(user);
        pool.updateRoot(123, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
    }

    /*//////////////////////////////////////////////////////////////
                          WIND DOWN
    //////////////////////////////////////////////////////////////*/

    function test_windDown() public {
        vm.prank(admin);
        pool.windDown();
        assertTrue(pool.dead());
    }

    /*//////////////////////////////////////////////////////////////
                       DIAMOND UPGRADE
    //////////////////////////////////////////////////////////////*/

    function test_upgradeDiamond_addFacet() public {
        // Deploy a new mock facet
        MockExtraFacet newFacet = new MockExtraFacet();

        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IPoolDiamond.ReplaceAction[] memory replaceFacets = new IPoolDiamond.ReplaceAction[](0);

        vm.prank(admin);
        pool.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        // Verify the new selector routes to the new facet
        assertEq(pool.facetAddress(MockExtraFacet.extraFunction.selector), address(newFacet));

        // Verify total facets increased
        assertEq(pool.facetAddresses().length, 9);
    }

    function test_upgradeDiamond_revertsForUnauthorized() public {
        address[] memory empty = new address[](0);
        IPoolDiamond.ReplaceAction[] memory emptyReplace = new IPoolDiamond.ReplaceAction[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ADMIN_ROLE
            )
        );
        vm.prank(user);
        pool.upgradeDiamond(empty, empty, emptyReplace);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAW FEES
    //////////////////////////////////////////////////////////////*/

    function test_withdrawFees_success() public {
        // Send some ETH to the diamond
        vm.deal(address(diamond), 1 ether);

        address recipient = makeAddr("feeCollector");
        uint256 recipientBefore = recipient.balance;

        vm.prank(admin);
        pool.withdrawFees(recipient);

        assertEq(recipient.balance - recipientBefore, 1 ether);
        assertEq(address(diamond).balance, 0);
    }

    function test_withdrawFees_revertsForZeroAddress() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.withdrawFees(address(0));
    }

    function test_withdrawFees_noOpForZeroBalance() public {
        // Diamond has no balance (beyond what setUp added)
        // Deploy fresh diamond with no ETH
        address recipient = makeAddr("feeCollector");
        uint256 recipientBefore = recipient.balance;
        uint256 diamondBalance = address(diamond).balance;

        vm.prank(admin);
        pool.withdrawFees(recipient);

        // Recipient gets whatever was in the diamond
        assertEq(recipient.balance - recipientBefore, diamondBalance);
    }

    function test_withdrawFees_revertsForUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ADMIN_ROLE
            )
        );
        vm.prank(user);
        pool.withdrawFees(user);
    }

    /*//////////////////////////////////////////////////////////////
                    CHAIN CONFIG EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalChainConfig_revertsForZeroOutputSettler() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(0), address(1), address(1), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForZeroOutputOracle() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(0), address(1), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForZeroFillOracle() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(0), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForShortDeadline() public {
        vm.expectRevert(AdminFacet.DeadlineTooShort.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 299, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForShortExpiry() public {
        vm.expectRevert(AdminFacet.DeadlineTooShort.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 3600, 299);
    }

    function test_setWithdrawalChainConfig_revertsForExpiryBeforeDeadline() public {
        vm.expectRevert(AdminFacet.ExpiryBeforeFillDeadline.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 3600, 3600);
    }

    function test_setDepositOutputSettler_revertsForZeroAddress() public {
        vm.expectRevert(AdminFacet.InvalidAddress.selector);
        vm.prank(admin);
        pool.setDepositOutputSettler(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    ASP ROOT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_updateRoot_revertsForShortCID() public {
        vm.expectRevert(AdminFacet.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, "QmShort"); // 7 chars, needs 32-64
    }

    function test_updateRoot_revertsForLongCID() public {
        // 65 character string (exceeds max of 64)
        string memory longCid = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdGExtraCharsHereNow!!";
        assert(bytes(longCid).length > 64);
        vm.expectRevert(AdminFacet.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, longCid);
    }

    /*//////////////////////////////////////////////////////////////
                    MAX SOLVER FEE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_setMaxSolverFeeBPS_revertsForUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, user, AccessControlStorageLib.ADMIN_ROLE
            )
        );
        vm.prank(user);
        pool.setMaxSolverFeeBPS(500);
    }

    function test_setMaxSolverFeeBPS_allowsZero() public {
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(0);
        assertEq(pool.maxSolverFeeBPS(), 0);
    }
}

/// @dev Mock facet for upgrade tests
contract MockExtraFacet is IFacet {
    function extraFunction() external pure returns (uint256) {
        return 42;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.extraFunction.selector);
    }
}
