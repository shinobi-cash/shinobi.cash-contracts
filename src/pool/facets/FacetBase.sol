// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {AccessControlOps} from "../libraries/AccessControlOps.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title FacetBase - Shared modifiers for diamond facets
abstract contract FacetBase {
    /// @dev Transient storage slot for reentrancy guard (EIP-1153)
    bytes32 private constant _REENTRANCY_SLOT = keccak256("shinobi.reentrancy.guard");

    error Reentrancy();

    modifier nonReentrant() {
        bytes32 slot = _REENTRANCY_SLOT;
        assembly {
            if tload(slot) {
                mstore(0x00, shl(224, 0xab143c06)) // Reentrancy()
                revert(0x00, 0x04)
            }
            tstore(slot, 1)
        }
        _;
        assembly {
            tstore(slot, 0)
        }
    }

    modifier onlyAdmin() {
        AccessControlOps.checkAdmin(msg.sender);
        _;
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
