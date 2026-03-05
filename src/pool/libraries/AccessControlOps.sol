// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlStorageData, AccessControlStorageLib} from "../storage/AccessControlStorage.sol";

library AccessControlOps {
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    error OnlyAdmin();
    error AccessControlUnauthorized(address account, bytes32 role);
    error AccessControlCannotRenounceOther(address account);

    function checkAdmin(address account) internal view {
        if (account != AccessControlStorageLib.layout().admin) revert OnlyAdmin();
    }

    function checkRole(bytes32 role, address account) internal view {
        AccessControlStorageData storage s = AccessControlStorageLib.layout();
        if (!s.roles[role].hasRole[account]) {
            revert AccessControlUnauthorized(account, role);
        }
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return AccessControlStorageLib.layout().roles[role].hasRole[account];
    }

    function grantRole(bytes32 role, address account) internal {
        AccessControlStorageData storage s = AccessControlStorageLib.layout();
        if (!s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function revokeRole(bytes32 role, address account) internal {
        AccessControlStorageData storage s = AccessControlStorageLib.layout();
        if (s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function renounceRole(bytes32 role, address callerConfirmation) internal {
        if (callerConfirmation != msg.sender) {
            revert AccessControlCannotRenounceOther(callerConfirmation);
        }
        AccessControlStorageData storage s = AccessControlStorageLib.layout();
        if (s.roles[role].hasRole[msg.sender]) {
            s.roles[role].hasRole[msg.sender] = false;
            emit RoleRevoked(role, msg.sender, msg.sender);
        }
    }
}
