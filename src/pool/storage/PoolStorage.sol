// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {LeanIMTData} from "lean-imt/InternalLeanIMT.sol";

/// @dev ASP association set data
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
    address outputFillOracle;
    address inputFillOracle;
}

/// @title PoolStorage - Unified pool state for the diamond
struct PoolStorageData {
    // Pool identity (set once in constructor)
    address asset;
    uint256 scope;

    // Merkle tree state
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

    // Fee config
    address vettingFeeRecipient;

    // Cross-chain withdrawal config
    address withdrawalInputSettler;
    uint256 maxSolverFeeBPS;
    uint256 maxRefundFeeBPS;
    mapping(uint256 => WithdrawalChainConfig) withdrawalChainConfig;

    // Cross-chain deposit config
    address depositOutputSettler;
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
