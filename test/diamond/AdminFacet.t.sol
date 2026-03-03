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
        uint256 index = pool.updateRoot(123, "QmNewRoot");

        assertEq(pool.latestRoot(), 123);
        (uint256 root, string memory cid, uint256 ts) = pool.associationSets(index);
        assertEq(root, 123);
        assertEq(cid, "QmNewRoot");
        assertEq(ts, block.timestamp);
    }

    function test_updateRoot_revertsForEmptyRoot() public {
        vm.expectRevert(AdminFacet.EmptyRoot.selector);
        vm.prank(aspPostman);
        pool.updateRoot(0, "QmTest");
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
        pool.updateRoot(123, "QmTest");
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

        vm.prank(diamondAdmin);
        pool.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        // Verify the new selector routes to the new facet
        assertEq(pool.facetAddress(MockExtraFacet.extraFunction.selector), address(newFacet));

        // Verify total facets increased
        assertEq(pool.facetAddresses().length, 10);
    }

    function test_upgradeDiamond_revertsForUnauthorized() public {
        address[] memory empty = new address[](0);
        IPoolDiamond.ReplaceAction[] memory emptyReplace = new IPoolDiamond.ReplaceAction[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlOps.AccessControlUnauthorized.selector, admin, AccessControlStorageLib.DIAMOND_ADMIN_ROLE
            )
        );
        vm.prank(admin);
        pool.upgradeDiamond(empty, empty, emptyReplace);
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
