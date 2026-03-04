// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFacet} from "../interfaces/IFacet.sol";
import {PoolStorageData, PoolStorageLib, AssociationSetData, WithdrawalChainConfig} from "../storage/PoolStorage.sol";
import {DiamondStorageData, DiamondStorageLib} from "../storage/DiamondStorage.sol";
import {AccessControlOps} from "../libraries/AccessControlOps.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title ViewFacet - Read-only views and ERC-8153 loupe functions
contract ViewFacet is IFacet {
    // ── Pool Identity ──

    function ASSET() external view returns (address) {
        return PoolStorageLib.layout().asset;
    }

    function SCOPE() external view returns (uint256) {
        return PoolStorageLib.layout().scope;
    }

    // ── Merkle Tree State ──

    function nonce() external view returns (uint256) {
        return PoolStorageLib.layout().nonce;
    }

    function dead() external view returns (bool) {
        return PoolStorageLib.layout().dead;
    }

    function roots(uint256 index) external view returns (uint256) {
        return PoolStorageLib.layout().roots[index];
    }

    function currentRootIndex() external view returns (uint32) {
        return PoolStorageLib.layout().currentRootIndex;
    }

    function currentRoot() external view returns (uint256) {
        PoolStorageData storage s = PoolStorageLib.layout();
        return s.roots[s.currentRootIndex];
    }

    function currentTreeDepth() external view returns (uint256) {
        return PoolStorageLib.layout().merkleTree.depth;
    }

    function currentTreeSize() external view returns (uint256) {
        return PoolStorageLib.layout().merkleTree.size;
    }

    function nullifierHashes(uint256 hash) external view returns (bool) {
        return PoolStorageLib.layout().nullifierHashes[hash];
    }

    function depositors(uint256 label) external view returns (address) {
        return PoolStorageLib.layout().depositors[label];
    }

    function usedPrecommitments(uint256 precommitment) external view returns (bool) {
        return PoolStorageLib.layout().usedPrecommitments[precommitment];
    }

    // ── Constants ──

    function ROOT_HISTORY_SIZE() external pure returns (uint32) {
        return PoolOps.ROOT_HISTORY_SIZE;
    }

    function MAX_TREE_DEPTH() external pure returns (uint32) {
        return PoolOps.MAX_TREE_DEPTH;
    }

    // ── ASP State ──

    function latestRoot() external view returns (uint256) {
        return PoolOps.latestASPRoot(PoolStorageLib.layout());
    }

    function rootByIndex(uint256 index) external view returns (uint256) {
        return PoolStorageLib.layout().associationSets[index].root;
    }

    function associationSets(uint256 index)
        external
        view
        returns (uint256 root, string memory ipfsCID, uint256 timestamp)
    {
        AssociationSetData storage data = PoolStorageLib.layout().associationSets[index];
        return (data.root, data.ipfsCID, data.timestamp);
    }

    // ── Asset Config ──

    function assetConfig()
        external
        view
        returns (uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS)
    {
        PoolStorageData storage s = PoolStorageLib.layout();
        return (s.minimumDepositAmount, s.vettingFeeBPS, s.maxRelayFeeBPS);
    }

    function maxSolverFeeBPS() external view returns (uint256) {
        return PoolStorageLib.layout().maxSolverFeeBPS;
    }

    function accumulatedFees() external view returns (uint256) {
        return PoolStorageLib.layout().accumulatedFees;
    }

    // ── Cross-chain Config ──

    function withdrawalInputSettler() external view returns (address) {
        return PoolStorageLib.layout().withdrawalInputSettler;
    }

    function depositOutputSettler() external view returns (address) {
        return PoolStorageLib.layout().depositOutputSettler;
    }

    function withdrawalChainConfig(uint256 chainId)
        external
        view
        returns (
            bool isConfigured,
            uint32 fillDeadline,
            uint32 expiry,
            address withdrawalOutputSettler,
            address withdrawalFillOracle,
            address fillOracle
        )
    {
        WithdrawalChainConfig storage config = PoolStorageLib.layout().withdrawalChainConfig[chainId];
        return (
            config.isConfigured,
            config.fillDeadline,
            config.expiry,
            config.withdrawalOutputSettler,
            config.withdrawalFillOracle,
            config.fillOracle
        );
    }

    // ── Access Control ──

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlOps.hasRole(role, account);
    }

    // ── ERC-8153 Loupe ──

    function facetAddress(bytes4 selector) external view returns (address) {
        return DiamondStorageLib.layout().selectorToFacet[selector];
    }

    function facetAddresses() external view returns (address[] memory) {
        return DiamondStorageLib.layout().facets;
    }

    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory) {
        return DiamondStorageLib.layout().facetSelectors[facet];
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(
            this.ASSET.selector,
            this.SCOPE.selector,
            this.nonce.selector,
            this.dead.selector,
            this.roots.selector,
            this.currentRootIndex.selector,
            this.currentRoot.selector,
            this.currentTreeDepth.selector,
            this.currentTreeSize.selector,
            this.nullifierHashes.selector,
            this.depositors.selector,
            this.usedPrecommitments.selector,
            this.ROOT_HISTORY_SIZE.selector,
            this.MAX_TREE_DEPTH.selector,
            this.latestRoot.selector,
            this.rootByIndex.selector,
            this.associationSets.selector,
            this.assetConfig.selector,
            this.maxSolverFeeBPS.selector,
            this.accumulatedFees.selector,
            this.withdrawalInputSettler.selector,
            this.depositOutputSettler.selector,
            this.withdrawalChainConfig.selector,
            this.hasRole.selector,
            this.facetAddress.selector,
            this.facetAddresses.selector,
            this.facetFunctionSelectors.selector
        );
    }
}
