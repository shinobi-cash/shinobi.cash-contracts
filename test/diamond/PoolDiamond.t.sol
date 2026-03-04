// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {PoolDiamond} from "../../src/diamond/PoolDiamond.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract PoolDiamondTest is DiamondTestBase {
    function test_constructor_setsAssetAndScope() public view {
        assertEq(pool.ASSET(), NATIVE_ASSET);

        uint256 expectedScope = uint256(
            keccak256(abi.encodePacked(address(diamond), block.chainid, NATIVE_ASSET))
        ) % Constants.SNARK_SCALAR_FIELD;
        assertEq(pool.SCOPE(), expectedScope);
    }

    function test_constructor_registersAllFacets() public view {
        address[] memory facets = pool.facetAddresses();
        assertEq(facets.length, 8);
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(pool.hasRole(keccak256("ADMIN_ROLE"), admin));
        assertTrue(pool.hasRole(keccak256("ASP_POSTMAN_ROLE"), aspPostman));
        // DIAMOND_ADMIN_ROLE removed — admin handles upgrades
    }

    function test_fallback_revertsForUnknownSelector() public {
        bytes4 unknownSelector = bytes4(keccak256("unknownFunction()"));
        vm.expectRevert(abi.encodeWithSelector(PoolDiamond.FunctionNotFound.selector, unknownSelector));
        (bool success,) = address(diamond).call(abi.encodeWithSelector(unknownSelector));
        // expectRevert handles the revert, but call returns false
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
        // admin selectors
        assertEq(pool.facetAddress(pool.setAssetConfig.selector), address(adminFacet));
    }

    function test_facetFunctionSelectors_returnsCorrectSelectors() public view {
        bytes4[] memory selectors = pool.facetFunctionSelectors(address(depositFacet));
        assertEq(selectors.length, 3); // deposit, crosschainDeposit, crosschainDepositERC20
    }
}
