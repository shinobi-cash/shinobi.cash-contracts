// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/**
 * @title ChainConfig
 * @notice Library for reading chain configuration from JSON
 * @dev Used by deployment scripts to get chain-specific addresses and settings
 */
library ChainConfig {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string constant POOLS_DIR = "script/config/pools/";
    string constant ORIGINS_DIR = "script/config/origins/";

    /*//////////////////////////////////////////////////////////////
                              POOL CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice Input configuration for pool chain deployment
    struct PoolConfig {
        string name;
        uint256 chainId;
        uint32 hyperlaneDomainId;
        address hyperlaneMailbox;
        address erc4337Entrypoint;
        // Config
        uint256 minimumDeposit;
        uint256 vettingFeeBPS;
        uint256 maxRelayFeeBPS;
        uint256 maxSolverFeeBPS;
        uint256 maxRefundFeeBPS;
        address vettingFeeRecipient;
    }

    /**
     * @notice Get pool configuration from config/pools/{poolKey}.json
     * @param poolKey The pool config file name without extension (e.g., "arbitrum-sepolia")
     */
    function getPoolConfig(string memory poolKey) internal view returns (PoolConfig memory config) {
        string memory path = string.concat(POOLS_DIR, poolKey, ".json");
        string memory json = vm.readFile(path);

        config.name = vm.parseJsonString(json, ".name");
        config.chainId = vm.parseJsonUint(json, ".chainId");
        config.hyperlaneDomainId = uint32(vm.parseJsonUint(json, ".hyperlaneDomainId"));
        config.hyperlaneMailbox = vm.parseJsonAddress(json, ".hyperlaneMailbox");
        config.erc4337Entrypoint = vm.parseJsonAddress(json, ".erc4337Entrypoint");

        // Config
        config.minimumDeposit = vm.parseJsonUint(json, ".config.minimumDeposit");
        config.vettingFeeBPS = vm.parseJsonUint(json, ".config.vettingFeeBPS");
        config.maxRelayFeeBPS = vm.parseJsonUint(json, ".config.maxRelayFeeBPS");
        config.maxSolverFeeBPS = vm.parseJsonUint(json, ".config.maxSolverFeeBPS");
        config.maxRefundFeeBPS = vm.parseJsonUint(json, ".config.maxRefundFeeBPS");
        config.vettingFeeRecipient = vm.parseJsonAddress(json, ".config.vettingFeeRecipient");
    }

    /*//////////////////////////////////////////////////////////////
                            ORIGIN CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice Input configuration for origin chain deployment
    struct OriginConfig {
        string name;
        uint256 chainId;
        uint32 hyperlaneDomainId;
        address hyperlaneMailbox;
        // Target pool
        string poolKey;
        // Config
        uint32 fillDeadline;
        uint32 expiry;
        uint256 minimumDepositAmount;
        uint256 defaultSolverFeeBPS;
        uint256 maxSolverFeeBPS;
    }

    /**
     * @notice Get origin chain configuration from config/origins/{originKey}.json
     * @param originKey The origin config file name without extension (e.g., "base-sepolia")
     */
    function getOriginConfig(string memory originKey) internal view returns (OriginConfig memory config) {
        string memory path = string.concat(ORIGINS_DIR, originKey, ".json");
        string memory json = vm.readFile(path);

        config.name = vm.parseJsonString(json, ".name");
        config.chainId = vm.parseJsonUint(json, ".chainId");
        config.hyperlaneDomainId = uint32(vm.parseJsonUint(json, ".hyperlaneDomainId"));
        config.hyperlaneMailbox = vm.parseJsonAddress(json, ".hyperlaneMailbox");
        config.poolKey = vm.parseJsonString(json, ".poolKey");

        // Config
        config.fillDeadline = uint32(vm.parseJsonUint(json, ".config.fillDeadline"));
        config.expiry = uint32(vm.parseJsonUint(json, ".config.expiry"));
        config.minimumDepositAmount = vm.parseJsonUint(json, ".config.minimumDepositAmount");
        config.defaultSolverFeeBPS = vm.parseJsonUint(json, ".config.defaultSolverFeeBPS");
        config.maxSolverFeeBPS = vm.parseJsonUint(json, ".config.maxSolverFeeBPS");
    }

}
