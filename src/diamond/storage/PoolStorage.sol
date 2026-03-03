// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LeanIMTData} from "lean-imt/InternalLeanIMT.sol";

/// @dev ASP association set data (previously from IEntrypoint)
struct AssociationSetData {
    uint256 root;
    string ipfsCID;
    uint256 timestamp;
}

/// @dev Withdrawal destination chain configuration
struct WithdrawalChainConfig {
    bool isConfigured;
    uint32 fillDeadline;
    uint32 expiry;
    address withdrawalOutputSettler;
    address withdrawalFillOracle;
    address fillOracle;
}

/// @title PoolStorage - Unified pool state for the diamond
struct PoolStorageData {
    // Pool identity (set once in constructor)
    address asset;
    uint256 scope;

    // Merkle tree state (from State.sol)
    uint256 nonce;
    bool dead;
    mapping(uint256 => uint256) roots;
    uint32 currentRootIndex;
    LeanIMTData merkleTree;
    mapping(uint256 => bool) nullifierHashes;
    mapping(uint256 => address) depositors;

    // ASP state
    AssociationSetData[] associationSets;
    mapping(uint256 => bool) usedPrecommitments;

    // Asset config
    uint256 minimumDepositAmount;
    uint256 vettingFeeBPS;
    uint256 maxRelayFeeBPS;

    // Cross-chain state
    address withdrawalInputSettler;
    address depositOutputSettler;
    uint256 maxSolverFeeBPS;
    mapping(uint256 => WithdrawalChainConfig) withdrawalChainConfig;

    // Reentrancy guard
    uint256 reentrancyStatus;
}

library PoolStorageLib {
    /// @dev keccak256("shinobi.pool.storage")
    bytes32 internal constant SLOT = 0xbd5d6792293dbb9464a07f2b07245696ac492f5b3d8ac5269785a1ad8eae870f;

    function layout() internal pure returns (PoolStorageData storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }
}
