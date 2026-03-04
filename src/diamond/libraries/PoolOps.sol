// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {PoolStorageData, AssociationSetData} from "../storage/PoolStorage.sol";

library PoolOps {
    using InternalLeanIMT for LeanIMTData;

    uint32 internal constant ROOT_HISTORY_SIZE = 64;
    uint32 internal constant MAX_TREE_DEPTH = 32;
    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;

    event LeafInserted(uint256 _index, uint256 _leaf, uint256 _root);

    error NullifierAlreadySpent();
    error UnknownStateRoot();
    error IncorrectASPRoot();
    error ContextMismatch();
    error InvalidTreeDepth();
    error PoolIsDead();
    error FailedToSendNativeAsset();
    error NoRootsAvailable();
    error InvalidWithdrawalAmount();
    error MaxTreeDepthReached();

    /// @notice Mark a nullifier as spent, revert if already spent
    function spend(PoolStorageData storage s, uint256 nullifierHash) internal {
        if (s.nullifierHashes[nullifierHash]) revert NullifierAlreadySpent();
        s.nullifierHashes[nullifierHash] = true;
    }

    /// @notice Insert a leaf into the Merkle tree, update the circular root buffer
    function insert(PoolStorageData storage s, uint256 leaf) internal returns (uint256 updatedRoot) {
        updatedRoot = s.merkleTree._insert(leaf);
        if (s.merkleTree.depth > MAX_TREE_DEPTH) revert MaxTreeDepthReached();
        uint32 newIndex = (s.currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        s.currentRootIndex = newIndex;
        s.roots[newIndex] = updatedRoot;
        emit LeafInserted(s.merkleTree.size, leaf, updatedRoot);
    }

    /// @notice Check if a root is in the circular buffer history
    function isKnownRoot(PoolStorageData storage s, uint256 root) internal view returns (bool) {
        if (root == 0) return false;
        uint32 idx = s.currentRootIndex;
        for (uint32 i; i < ROOT_HISTORY_SIZE; ++i) {
            if (s.roots[idx] == root) return true;
            if (idx == 0) idx = ROOT_HISTORY_SIZE - 1;
            else --idx;
        }
        return false;
    }

    /// @notice Get the latest ASP root
    function latestASPRoot(PoolStorageData storage s) internal view returns (uint256) {
        uint256 len = s.associationSets.length;
        if (len == 0) revert NoRootsAvailable();
        return s.associationSets[len - 1].root;
    }

    /// @notice Transfer native ETH to a recipient
    function transferETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert FailedToSendNativeAsset();
    }

    /// @notice Deduct a fee from an amount
    function deductFee(uint256 amount, uint256 feeBPS) internal pure returns (uint256) {
        return amount - (amount * feeBPS / 10_000);
    }

    /// @notice Calculate fee amount from value and BPS
    function calculateFee(uint256 amount, uint256 feeBPS) internal pure returns (uint256) {
        return amount * feeBPS / 10_000;
    }

    /// @notice Validate proof context matches keccak256(withdrawal, scope) % SNARK_SCALAR_FIELD
    function validateProofContext(
        PoolStorageData storage s,
        IPrivacyPool.Withdrawal memory withdrawal,
        uint256 context
    ) internal view {
        uint256 expectedContext =
            uint256(keccak256(abi.encode(withdrawal, s.scope))) % Constants.SNARK_SCALAR_FIELD;
        if (context != expectedContext) revert ContextMismatch();
    }

    /// @notice Validate tree depths are within max
    function validateTreeDepths(uint256 stateDepth, uint256 aspDepth) internal pure {
        if (stateDepth > MAX_TREE_DEPTH || aspDepth > MAX_TREE_DEPTH) {
            revert InvalidTreeDepth();
        }
    }

    /// @notice Validate the state root is known
    function validateStateRoot(PoolStorageData storage s, uint256 root) internal view {
        if (!isKnownRoot(s, root)) revert UnknownStateRoot();
    }

    /// @notice Validate the ASP root matches the latest
    function validateASPRoot(PoolStorageData storage s, uint256 aspRoot) internal view {
        if (aspRoot != latestASPRoot(s)) revert IncorrectASPRoot();
    }
}
