// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib, AssociationSetData, WithdrawalChainConfig} from "../storage/PoolStorage.sol";
import {AccessControlStorageLib} from "../storage/AccessControlStorage.sol";
import {AccessControlOps} from "../libraries/AccessControlOps.sol";
import {DiamondOps} from "../libraries/DiamondOps.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title AdminFacet - Configuration and role management for the pool diamond
contract AdminFacet is FacetBase, IFacet {
    // Events
    event RootUpdated(uint256 root, string ipfsCID, uint256 timestamp);
    event AssetConfigUpdated(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS);
    event WithdrawalInputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event DepositOutputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event MaxSolverFeeBPSUpdated(uint256 oldValue, uint256 newValue);
    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    );
    event PoolDied();
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    // Errors
    error InvalidIPFSCIDLength();
    error EmptyRoot();
    error InvalidFeeBPS();
    error InvalidAddress();
    error InvalidChainId();
    error DeadlineTooShort();
    error ExpiryBeforeFillDeadline();

    // ── Role Management ──

    function grantRole(bytes32 role, address account) external onlyRole(AccessControlOps.getAdminRole(role)) {
        AccessControlOps.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(AccessControlOps.getAdminRole(role)) {
        AccessControlOps.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        AccessControlOps.renounceRole(role, callerConfirmation);
    }

    // ── Pool Configuration ──

    function setAssetConfig(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS)
        external
        onlyRole(AccessControlStorageLib.ADMIN_ROLE)
    {
        if (vettingFeeBPS > 10_000 || maxRelayFeeBPS > 10_000) revert InvalidFeeBPS();
        PoolStorageData storage s = PoolStorageLib.layout();
        s.minimumDepositAmount = minimumDepositAmount;
        s.vettingFeeBPS = vettingFeeBPS;
        s.maxRelayFeeBPS = maxRelayFeeBPS;
        emit AssetConfigUpdated(minimumDepositAmount, vettingFeeBPS, maxRelayFeeBPS);
    }

    function setMaxSolverFeeBPS(uint256 maxSolverFeeBPS)
        external
        onlyRole(AccessControlStorageLib.ADMIN_ROLE)
    {
        if (maxSolverFeeBPS > 10_000) revert InvalidFeeBPS();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit MaxSolverFeeBPSUpdated(s.maxSolverFeeBPS, maxSolverFeeBPS);
        s.maxSolverFeeBPS = maxSolverFeeBPS;
    }

    function setWithdrawalInputSettler(address settler)
        external
        onlyRole(AccessControlStorageLib.ADMIN_ROLE)
    {
        if (settler == address(0)) revert InvalidAddress();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit WithdrawalInputSettlerUpdated(s.withdrawalInputSettler, settler);
        s.withdrawalInputSettler = settler;
    }

    function setDepositOutputSettler(address settler)
        external
        onlyRole(AccessControlStorageLib.ADMIN_ROLE)
    {
        if (settler == address(0)) revert InvalidAddress();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit DepositOutputSettlerUpdated(s.depositOutputSettler, settler);
        s.depositOutputSettler = settler;
    }

    function setWithdrawalChainConfig(
        uint256 chainId,
        address outputSettler,
        address outputOracle,
        address fillOracle,
        uint32 fillDeadline,
        uint32 expiry
    ) external onlyRole(AccessControlStorageLib.ADMIN_ROLE) {
        if (chainId == 0) revert InvalidChainId();
        if (fillDeadline == 0) revert DeadlineTooShort();
        if (expiry <= fillDeadline) revert ExpiryBeforeFillDeadline();

        PoolStorageData storage s = PoolStorageLib.layout();
        s.withdrawalChainConfig[chainId] = WithdrawalChainConfig({
            isConfigured: true,
            fillDeadline: fillDeadline,
            expiry: expiry,
            withdrawalOutputSettler: outputSettler,
            withdrawalFillOracle: outputOracle,
            fillOracle: fillOracle
        });

        emit WithdrawalChainConfigured(chainId, fillDeadline, expiry, outputSettler, outputOracle, fillOracle);
    }

    // ── ASP Root ──

    function updateRoot(uint256 root, string calldata ipfsCID)
        external
        onlyRole(AccessControlStorageLib.ASP_POSTMAN_ROLE)
        returns (uint256 index)
    {
        if (root == 0) revert EmptyRoot();
        if (bytes(ipfsCID).length == 0) revert InvalidIPFSCIDLength();

        PoolStorageData storage s = PoolStorageLib.layout();
        s.associationSets.push(AssociationSetData({root: root, ipfsCID: ipfsCID, timestamp: block.timestamp}));
        index = s.associationSets.length - 1;
        emit RootUpdated(root, ipfsCID, block.timestamp);
    }

    // ── Pool Lifecycle ──

    function windDown() external onlyRole(AccessControlStorageLib.ADMIN_ROLE) {
        PoolStorageData storage s = PoolStorageLib.layout();
        s.dead = true;
        emit PoolDied();
    }

    function withdrawFees(address recipient)
        external
        nonReentrant
        onlyRole(AccessControlStorageLib.ADMIN_ROLE)
    {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 balance = address(this).balance;
        if (balance > 0) {
            PoolOps.transferETH(recipient, balance);
            emit FeesWithdrawn(recipient, balance);
        }
    }

    // ── Diamond Upgrade (ERC-8153) ──

    function upgradeDiamond(
        address[] calldata addFacets,
        address[] calldata removeFacets,
        ReplaceAction[] calldata replaceFacets
    ) external onlyRole(AccessControlStorageLib.DIAMOND_ADMIN_ROLE) {
        for (uint256 i; i < removeFacets.length; ++i) {
            DiamondOps.removeFacet(removeFacets[i]);
        }
        for (uint256 i; i < replaceFacets.length; ++i) {
            DiamondOps.replaceFacet(replaceFacets[i].oldFacet, replaceFacets[i].newFacet);
        }
        for (uint256 i; i < addFacets.length; ++i) {
            DiamondOps.addFacet(addFacets[i]);
        }
    }

    struct ReplaceAction {
        address oldFacet;
        address newFacet;
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(
            this.grantRole.selector,
            this.revokeRole.selector,
            this.renounceRole.selector,
            this.setAssetConfig.selector,
            this.setMaxSolverFeeBPS.selector,
            this.setWithdrawalInputSettler.selector,
            this.setDepositOutputSettler.selector,
            this.setWithdrawalChainConfig.selector,
            this.updateRoot.selector,
            this.windDown.selector,
            this.withdrawFees.selector,
            this.upgradeDiamond.selector
        );
    }
}
