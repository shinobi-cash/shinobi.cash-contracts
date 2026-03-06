// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase, MockInputSettler} from "./DiamondTestBase.sol";
import {PoolDiamond} from "../../../src/pool/PoolDiamond.sol";
import {AccessControlOps} from "../../../src/pool/libraries/AccessControlOps.sol";
import {AccessControlStorageLib} from "../../../src/pool/storage/AccessControlStorage.sol";
import {IFacet} from "../../../src/pool/interfaces/IFacet.sol";
import {IPoolDiamond} from "../../../src/pool/interfaces/IPoolDiamond.sol";
import {Constants} from "../../../src/pool/libraries/Constants.sol";

contract PoolDiamondTest is DiamondTestBase {
    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructor_setsAssetAndScope() public view {
        assertEq(pool.ASSET(), NATIVE_ASSET);

        uint256 expectedScope = uint256(
            keccak256(abi.encodePacked(address(diamond), block.chainid, NATIVE_ASSET))
        ) % Constants.SNARK_SCALAR_FIELD;
        assertEq(pool.SCOPE(), expectedScope);
    }

    function test_constructor_registersAllFacets() public view {
        address[] memory facets = pool.facetAddresses();
        assertEq(facets.length, 7);
    }

    function test_constructor_setsAdmin() public view {
        assertEq(pool.admin(), admin);
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(pool.hasRole(keccak256("ASP_POSTMAN_ROLE"), aspPostman));
    }

    function test_fallback_revertsForUnknownSelector() public {
        bytes4 unknownSelector = bytes4(keccak256("unknownFunction()"));
        vm.expectRevert(abi.encodeWithSelector(PoolDiamond.FunctionNotFound.selector, unknownSelector));
        (bool success,) = address(diamond).call(abi.encodeWithSelector(unknownSelector));
        assertTrue(!success || true); // expectRevert already asserted
    }

    function test_receive_acceptsETH() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success,) = address(diamond).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(diamond).balance, 1 ether);
    }

    function test_facetAddress_routesCorrectly() public view {
        // deposit selector should route to DepositFacet
        assertEq(pool.facetAddress(pool.deposit.selector), address(depositFacet));
        // withdraw selector should route to WithdrawFacet
        assertEq(pool.facetAddress(pool.withdraw.selector), address(withdrawFacet));
    }

    function test_facetFunctionSelectors_returnsCorrectSelectors() public view {
        bytes4[] memory selectors = pool.facetFunctionSelectors(address(depositFacet));
        assertEq(selectors.length, 1); // deposit
    }

    /*//////////////////////////////////////////////////////////////
                         ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_grantRole_byAdmin() public {
        address newPostman = makeAddr("newPostman");
        vm.prank(admin);
        pool.grantRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman);
        assertTrue(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman));
    }

    function test_grantRole_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
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
                       2-STEP ADMIN TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_transferAdmin_success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        pool.transferAdmin(newAdmin);

        assertEq(pool.pendingAdmin(), newAdmin);
    }

    function test_transferAdmin_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.transferAdmin(user);
    }

    function test_transferAdmin_revertsForZeroAddress() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.transferAdmin(address(0));
    }

    function test_acceptAdmin_success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        pool.transferAdmin(newAdmin);

        vm.prank(newAdmin);
        pool.acceptAdmin();

        assertEq(pool.admin(), newAdmin);
        assertEq(pool.pendingAdmin(), address(0));
    }

    function test_acceptAdmin_revertsForNonPending() public {
        vm.expectRevert(PoolDiamond.NotPendingAdmin.selector);
        vm.prank(user);
        pool.acceptAdmin();
    }

    function test_acceptAdmin_replacesOldAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        pool.transferAdmin(newAdmin);

        vm.prank(newAdmin);
        pool.acceptAdmin();

        // Old admin can no longer call admin functions
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(100);

        // New admin can
        vm.prank(newAdmin);
        pool.setMaxSolverFeeBPS(100);
        assertEq(pool.maxSolverFeeBPS(), 100);
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
        vm.expectRevert(PoolDiamond.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setAssetConfig(0.01 ether, 10_001, 500);
    }

    function test_setAssetConfig_revertsForZeroMinDeposit() public {
        vm.expectRevert(PoolDiamond.InvalidAssetConfig.selector);
        vm.prank(admin);
        pool.setAssetConfig(0, 100, 500);
    }

    function test_setAssetConfig_revertsForZeroMaxRelayFee() public {
        vm.expectRevert(PoolDiamond.InvalidAssetConfig.selector);
        vm.prank(admin);
        pool.setAssetConfig(0.01 ether, 100, 0);
    }

    function test_setAssetConfig_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.setAssetConfig(0.01 ether, 100, 500);
    }

    /*//////////////////////////////////////////////////////////////
                          SETTLERS
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalInputSettler() public {
        MockInputSettler newSettler = new MockInputSettler();
        newSettler.setEntrypoint(address(diamond));
        vm.prank(admin);
        pool.setWithdrawalInputSettler(address(newSettler));
        assertEq(pool.withdrawalInputSettler(), address(newSettler));
    }

    function test_setWithdrawalInputSettler_revertsForZeroAddress() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalInputSettler(address(0));
    }

    function test_setWithdrawalInputSettler_revertsForWrongEntrypoint() public {
        MockInputSettler wrongSettler = new MockInputSettler();
        wrongSettler.setEntrypoint(makeAddr("wrongPool"));
        vm.expectRevert(PoolDiamond.InvalidSettlerEntrypoint.selector);
        vm.prank(admin);
        pool.setWithdrawalInputSettler(address(wrongSettler));
    }

    function test_setDepositOutputSettler() public {
        address newSettler = makeAddr("newSettler");
        vm.etch(newSettler, hex"00");
        vm.prank(admin);
        pool.setDepositOutputSettler(newSettler);
        assertEq(pool.depositOutputSettler(), newSettler);
    }

    function test_setDepositOutputSettler_revertsForZeroAddress() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setDepositOutputSettler(address(0));
    }

    function test_setDepositOutputSettler_revertsForEOA() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setDepositOutputSettler(eoa);
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
        vm.expectRevert(PoolDiamond.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(10_001);
    }

    function test_setMaxSolverFeeBPS_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.setMaxSolverFeeBPS(500);
    }

    function test_setMaxSolverFeeBPS_allowsZero() public {
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(0);
        assertEq(pool.maxSolverFeeBPS(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          MAX REFUND FEE
    //////////////////////////////////////////////////////////////*/

    function test_setMaxRefundFeeBPS() public {
        vm.prank(admin);
        pool.setMaxRefundFeeBPS(300);
        assertEq(pool.maxRefundFeeBPS(), 300);
    }

    function test_setMaxRefundFeeBPS_revertsForZero() public {
        vm.expectRevert(PoolDiamond.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setMaxRefundFeeBPS(0);
    }

    function test_setMaxRefundFeeBPS_revertsForInvalidBPS() public {
        vm.expectRevert(PoolDiamond.InvalidFeeBPS.selector);
        vm.prank(admin);
        pool.setMaxRefundFeeBPS(10_000);
    }

    function test_setMaxRefundFeeBPS_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.setMaxRefundFeeBPS(500);
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
        vm.expectRevert(PoolDiamond.InvalidChainId.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(0, address(1), address(1), address(1), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForZeroOutputSettler() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(0), address(1), address(1), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForZeroOutputOracle() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(0), address(1), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForZeroFillOracle() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(0), 3600, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForShortDeadline() public {
        vm.expectRevert(PoolDiamond.DeadlineTooShort.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 299, 7200);
    }

    function test_setWithdrawalChainConfig_revertsForShortExpiry() public {
        vm.expectRevert(PoolDiamond.DeadlineTooShort.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 3600, 299);
    }

    function test_setWithdrawalChainConfig_revertsForExpiryBeforeDeadline() public {
        vm.expectRevert(PoolDiamond.ExpiryBeforeFillDeadline.selector);
        vm.prank(admin);
        pool.setWithdrawalChainConfig(84532, address(1), address(1), address(1), 3600, 3600);
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
        vm.expectRevert(PoolDiamond.EmptyRoot.selector);
        vm.prank(aspPostman);
        pool.updateRoot(0, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
    }

    function test_updateRoot_revertsForEmptyCID() public {
        vm.expectRevert(PoolDiamond.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, "");
    }

    function test_updateRoot_revertsForShortCID() public {
        vm.expectRevert(PoolDiamond.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, "QmShort");
    }

    function test_updateRoot_revertsForLongCID() public {
        string memory longCid = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdGExtraCharsHereNow!!";
        assert(bytes(longCid).length > 64);
        vm.expectRevert(PoolDiamond.InvalidIPFSCIDLength.selector);
        vm.prank(aspPostman);
        pool.updateRoot(123, longCid);
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
        MockExtraFacet newFacet = new MockExtraFacet();

        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IPoolDiamond.ReplaceAction[] memory replaceFacets = new IPoolDiamond.ReplaceAction[](0);

        vm.prank(admin);
        pool.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        assertEq(pool.facetAddress(MockExtraFacet.extraFunction.selector), address(newFacet));
        assertEq(pool.facetAddresses().length, 8);
    }

    function test_upgradeDiamond_revertsForNonAdmin() public {
        address[] memory empty = new address[](0);
        IPoolDiamond.ReplaceAction[] memory emptyReplace = new IPoolDiamond.ReplaceAction[](0);

        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.upgradeDiamond(empty, empty, emptyReplace);
    }

    /*//////////////////////////////////////////////////////////////
                       VETTING FEE RECIPIENT
    //////////////////////////////////////////////////////////////*/

    function test_setVettingFeeRecipient_success() public {
        address newRecipient = makeAddr("newVault");
        vm.prank(admin);
        pool.setVettingFeeRecipient(newRecipient);
        assertEq(pool.vettingFeeRecipient(), newRecipient);
    }

    function test_setVettingFeeRecipient_revertsForZeroAddress() public {
        vm.expectRevert(PoolDiamond.InvalidAddress.selector);
        vm.prank(admin);
        pool.setVettingFeeRecipient(address(0));
    }

    function test_setVettingFeeRecipient_revertsForNonAdmin() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(user);
        pool.setVettingFeeRecipient(user);
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
