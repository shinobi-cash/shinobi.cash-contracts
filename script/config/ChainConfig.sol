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

    // Legacy config path (deprecated)
    string constant CONFIG_PATH = "script/config/chains.json";

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

    /*//////////////////////////////////////////////////////////////
                        LEGACY (DEPRECATED)
    //////////////////////////////////////////////////////////////*/

    struct PoolChainVerifiers {
        address withdrawal;
        address commitment;
        address crossChainWithdrawal;
        address withdraw2;
        address crosschainWithdraw2;
    }

    struct PoolChainPaymasters {
        address simple;
        address crossChain;
        address withdraw2;
        address crosschainWithdraw2;
    }

    struct PoolChainConfig {
        string name;
        uint256 chainId;
        uint32 hyperlaneDomainId;
        address hyperlaneMailbox;
        address erc4337Entrypoint;
        // Config
        uint256 minimumDeposit;
        uint256 vettingFeeBPS;
        uint256 maxRelayFeeBPS;
        // Contracts
        address entrypoint;
        address ethPool;
        address inputSettler;
        address depositOutputSettler;
        address hyperlaneOracle;
    }

    struct SupportedChainConfig {
        string name;
        uint256 chainId;
        uint32 hyperlaneDomainId;
        address hyperlaneMailbox;
        bool enabled;
        // Config
        uint32 fillDeadline;
        uint32 expiry;
        uint256 minimumDepositAmount;
        uint256 defaultSolverFeeBPS;
        uint256 maxSolverFeeBPS;
        // Contracts
        address hyperlaneOracle;
        address depositEntrypoint;
        address inputSettler;
        address withdrawalOutputSettler;
    }

    /**
     * @notice Get pool chain configuration (DEPRECATED - use getPoolConfig)
     */
    function getPoolChainConfig() internal view returns (PoolChainConfig memory config) {
        string memory json = vm.readFile(CONFIG_PATH);

        config.name = vm.parseJsonString(json, ".poolChain.name");
        config.chainId = vm.parseJsonUint(json, ".poolChain.chainId");
        config.hyperlaneDomainId = uint32(vm.parseJsonUint(json, ".poolChain.hyperlaneDomainId"));
        config.hyperlaneMailbox = vm.parseJsonAddress(json, ".poolChain.hyperlaneMailbox");
        config.erc4337Entrypoint = vm.parseJsonAddress(json, ".poolChain.erc4337Entrypoint");

        // Config
        config.minimumDeposit = vm.parseJsonUint(json, ".poolChain.config.minimumDeposit");
        config.vettingFeeBPS = vm.parseJsonUint(json, ".poolChain.config.vettingFeeBPS");
        config.maxRelayFeeBPS = vm.parseJsonUint(json, ".poolChain.config.maxRelayFeeBPS");

        // Contracts - handle empty addresses
        config.entrypoint = _parseAddressOrZero(json, ".poolChain.contracts.entrypoint");
        config.ethPool = _parseAddressOrZero(json, ".poolChain.contracts.ethPool");
        config.inputSettler = _parseAddressOrZero(json, ".poolChain.contracts.inputSettler");
        config.depositOutputSettler = _parseAddressOrZero(json, ".poolChain.contracts.depositOutputSettler");
        config.hyperlaneOracle = _parseAddressOrZero(json, ".poolChain.contracts.hyperlaneOracle");
    }

    /**
     * @notice Get pool chain verifier addresses (DEPRECATED)
     */
    function getPoolChainVerifiers() internal view returns (PoolChainVerifiers memory verifiers) {
        string memory json = vm.readFile(CONFIG_PATH);

        verifiers.withdrawal = _parseAddressOrZero(json, ".poolChain.verifiers.withdrawal");
        verifiers.commitment = _parseAddressOrZero(json, ".poolChain.verifiers.commitment");
        verifiers.crossChainWithdrawal = _parseAddressOrZero(json, ".poolChain.verifiers.crossChainWithdrawal");
        verifiers.withdraw2 = _parseAddressOrZero(json, ".poolChain.verifiers.withdraw2");
        verifiers.crosschainWithdraw2 = _parseAddressOrZero(json, ".poolChain.verifiers.crosschainWithdraw2");
    }

    /**
     * @notice Get pool chain paymaster addresses (DEPRECATED)
     */
    function getPoolChainPaymasters() internal view returns (PoolChainPaymasters memory paymasters) {
        string memory json = vm.readFile(CONFIG_PATH);

        paymasters.simple = _parseAddressOrZero(json, ".poolChain.paymasters.simple");
        paymasters.crossChain = _parseAddressOrZero(json, ".poolChain.paymasters.crossChain");
        paymasters.withdraw2 = _parseAddressOrZero(json, ".poolChain.paymasters.withdraw2");
        paymasters.crosschainWithdraw2 = _parseAddressOrZero(json, ".poolChain.paymasters.crosschainWithdraw2");
    }

    /**
     * @notice Get configuration for a supported chain by key (DEPRECATED - use getOriginConfig)
     * @param chainKey The key in supportedChains (e.g., "baseSepolia", "optimismSepolia")
     */
    function getSupportedChainConfig(string memory chainKey) internal view returns (SupportedChainConfig memory config) {
        string memory json = vm.readFile(CONFIG_PATH);
        string memory basePath = string.concat(".supportedChains.", chainKey);

        config.name = vm.parseJsonString(json, string.concat(basePath, ".name"));
        config.chainId = vm.parseJsonUint(json, string.concat(basePath, ".chainId"));
        config.hyperlaneDomainId = uint32(vm.parseJsonUint(json, string.concat(basePath, ".hyperlaneDomainId")));
        config.hyperlaneMailbox = vm.parseJsonAddress(json, string.concat(basePath, ".hyperlaneMailbox"));
        config.enabled = vm.parseJsonBool(json, string.concat(basePath, ".enabled"));

        // Config section
        config.fillDeadline = uint32(vm.parseJsonUint(json, string.concat(basePath, ".config.fillDeadline")));
        config.expiry = uint32(vm.parseJsonUint(json, string.concat(basePath, ".config.expiry")));
        config.minimumDepositAmount = vm.parseJsonUint(json, string.concat(basePath, ".config.minimumDepositAmount"));
        config.defaultSolverFeeBPS = vm.parseJsonUint(json, string.concat(basePath, ".config.defaultSolverFeeBPS"));
        config.maxSolverFeeBPS = vm.parseJsonUint(json, string.concat(basePath, ".config.maxSolverFeeBPS"));

        // Contracts section - handle empty strings
        config.hyperlaneOracle = _parseAddressOrZero(json, string.concat(basePath, ".contracts.hyperlaneOracle"));
        config.depositEntrypoint = _parseAddressOrZero(json, string.concat(basePath, ".contracts.depositEntrypoint"));
        config.inputSettler = _parseAddressOrZero(json, string.concat(basePath, ".contracts.inputSettler"));
        config.withdrawalOutputSettler = _parseAddressOrZero(json, string.concat(basePath, ".contracts.withdrawalOutputSettler"));
    }

    /**
     * @notice Helper to parse address or return zero if empty/invalid
     */
    function _parseAddressOrZero(string memory json, string memory path) private pure returns (address) {
        try vm.parseJsonAddress(json, path) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }
}
