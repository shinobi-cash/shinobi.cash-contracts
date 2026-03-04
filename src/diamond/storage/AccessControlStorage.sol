// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

struct RoleData {
    mapping(address => bool) hasRole;
    bytes32 adminRole;
}

/// @title AccessControlStorage - Role-based access control state
struct AccessControlStorageData {
    mapping(bytes32 => RoleData) roles;
    address pendingAdmin;
}

library AccessControlStorageLib {
    /// @dev keccak256("shinobi.accesscontrol.storage")
    bytes32 internal constant SLOT = 0xf8e936e752235399ec6bbd1ebde00142f41297201da54f82d3eb7014eb03c805;

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant ASP_POSTMAN_ROLE = keccak256("ASP_POSTMAN_ROLE");

    function layout() internal pure returns (AccessControlStorageData storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }
}
