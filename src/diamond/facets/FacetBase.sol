// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {AccessControlOps} from "../libraries/AccessControlOps.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title FacetBase - Shared modifiers for diamond facets
abstract contract FacetBase {
    modifier nonReentrant() {
        PoolStorageData storage s = PoolStorageLib.layout();
        require(s.reentrancyStatus != PoolOps.ENTERED, "ReentrancyGuard");
        s.reentrancyStatus = PoolOps.ENTERED;
        _;
        s.reentrancyStatus = PoolOps.NOT_ENTERED;
    }

    modifier onlyRole(bytes32 role) {
        AccessControlOps.checkRole(role, msg.sender);
        _;
    }

    modifier whenAlive() {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (s.dead) revert PoolOps.PoolIsDead();
        _;
    }
}
