// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Constants} from "contracts/lib/Constants.sol";
import {PoolStorageData, PoolStorageLib} from "./storage/PoolStorage.sol";
import {DiamondStorageData, DiamondStorageLib} from "./storage/DiamondStorage.sol";
import {AccessControlStorageLib} from "./storage/AccessControlStorage.sol";
import {DiamondOps} from "./libraries/DiamondOps.sol";
import {AccessControlOps} from "./libraries/AccessControlOps.sol";
import {PoolOps} from "./libraries/PoolOps.sol";

/// @title PoolDiamond - ERC-8153 diamond proxy for Shinobi Cash privacy pools
/// @notice Single-address pool supporting multiple operation types as facets
contract PoolDiamond {
    struct InitParams {
        address asset;
        address admin;
        address aspPostman;
        address[] facets;
    }

    error FunctionNotFound(bytes4 selector);

    constructor(InitParams memory params) payable {
        // Initialize pool storage
        PoolStorageData storage ps = PoolStorageLib.layout();
        ps.asset = params.asset;
        ps.scope =
            uint256(keccak256(abi.encodePacked(address(this), block.chainid, params.asset))) % Constants.SNARK_SCALAR_FIELD;
        ps.reentrancyStatus = PoolOps.NOT_ENTERED;

        // Initialize access control
        // ADMIN_ROLE is self-administering
        AccessControlOps.setAdminRole(AccessControlStorageLib.ADMIN_ROLE, AccessControlStorageLib.ADMIN_ROLE);
        AccessControlOps.grantRole(AccessControlStorageLib.ADMIN_ROLE, params.admin);

        // ASP_POSTMAN_ROLE administered by ADMIN_ROLE
        AccessControlOps.setAdminRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, AccessControlStorageLib.ADMIN_ROLE);
        AccessControlOps.grantRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, params.aspPostman);

        // Register all facets via ERC-8153 on-chain discovery
        for (uint256 i; i < params.facets.length; ++i) {
            DiamondOps.addFacet(params.facets[i]);
        }
    }

    fallback() external payable {
        DiamondStorageData storage ds = DiamondStorageLib.layout();
        address facet = ds.selectorToFacet[msg.sig];
        if (facet == address(0)) revert FunctionNotFound(msg.sig);

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
