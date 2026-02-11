// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Contracts to configure
import {ShinobiCashEntrypoint} from "../../src/core/ShinobiCashEntrypoint.sol";
import {ShinobiDepositOutputSettler} from "../../src/oif/ShinobiDepositOutputSettler.sol";

/**
 * @title AddChain_02_ConfigurePoolChain
 * @notice Configure pool chain to support a new origin/destination chain
 * @dev Run this script on the POOL CHAIN
 *
 * Input:  config/origins/{ORIGIN_KEY}.json
 * Reads:  deployments/{pool-key}.json, deployments/{origin-name}.json
 *
 * Usage:
 *   ORIGIN_KEY=base-sepolia forge script script/chains/AddChain_02_ConfigurePoolChain.s.sol --rpc-url arbitrum-sepolia --broadcast
 */
contract AddChain_02_ConfigurePoolChain is Script {
    struct PoolAddresses {
        address entrypoint;
        address depositOutputSettler;
        address hyperlaneOracle;
    }

    struct OriginAddresses {
        address hyperlaneOracle;
        address depositEntrypoint;
        address withdrawalOutputSettler;
    }

    function run() external {
        string memory originKey = vm.envString("ORIGIN_KEY");

        // Load configurations
        ChainConfig.OriginConfig memory originConfig = ChainConfig.getOriginConfig(originKey);
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(originConfig.poolKey);

        require(block.chainid == poolConfig.chainId, "Must run on pool chain!");

        string memory poolChainName = _sanitizeChainName(poolConfig.name);
        string memory originChainName = _sanitizeChainName(originConfig.name);

        PoolAddresses memory pool = _readPoolAddresses(poolChainName);
        OriginAddresses memory origin = _readOriginAddresses(originChainName);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  ADD NEW CHAIN - Step 2: Configure Pool Chain");
        console.log("==========================================================");
        console.log("");
        console.log("Origin Key:", originKey);
        console.log("Pool Chain:", poolConfig.name);
        console.log("New Origin Chain:", originConfig.name);
        console.log("Origin Chain ID:", originConfig.chainId);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        _configureDepositOutputSettler(pool.depositOutputSettler, originConfig.chainId, origin);
        _configureEntrypoint(pool.entrypoint, pool.hyperlaneOracle, originConfig, origin);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  POOL CHAIN CONFIGURATION COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: ORIGIN_KEY=%s forge script AddChain_03_ConfigureOriginChain.s.sol --rpc-url <origin-chain>", originKey);
    }

    function _readPoolAddresses(string memory chainName) internal view returns (PoolAddresses memory) {
        PoolAddresses memory pool;
        pool.entrypoint = DeploymentWriter.readContractAddress(chainName, "contracts", "entrypoint");
        pool.depositOutputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "depositOutputSettler");
        pool.hyperlaneOracle = DeploymentWriter.readContractAddress(chainName, "contracts", "hyperlaneOracle");

        require(pool.entrypoint != address(0), "Pool Entrypoint not deployed");
        require(pool.depositOutputSettler != address(0), "Pool DepositOutputSettler not deployed");
        require(pool.hyperlaneOracle != address(0), "Pool HyperlaneOracle not deployed");

        return pool;
    }

    function _readOriginAddresses(string memory chainName) internal view returns (OriginAddresses memory) {
        OriginAddresses memory origin;
        origin.hyperlaneOracle = DeploymentWriter.readContractAddress(chainName, "contracts", "hyperlaneOracle");
        origin.depositEntrypoint = DeploymentWriter.readContractAddress(chainName, "contracts", "depositEntrypoint");
        origin.withdrawalOutputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "withdrawalOutputSettler");

        require(origin.hyperlaneOracle != address(0), "Origin HyperlaneOracle not deployed");
        require(origin.depositEntrypoint != address(0), "Origin DepositEntrypoint not deployed");
        require(origin.withdrawalOutputSettler != address(0), "Origin WithdrawalOutputSettler not deployed");

        return origin;
    }

    function _configureDepositOutputSettler(
        address settler,
        uint256 originChainId,
        OriginAddresses memory origin
    ) internal {
        console.log("1. Configuring DepositOutputSettler...");

        ShinobiDepositOutputSettler settlerContract = ShinobiDepositOutputSettler(payable(settler));

        // Check if already configured using try-catch (handles version mismatches)
        try settlerContract.originChainConfigs(originChainId) returns (address, address, bool isConfigured) {
            if (isConfigured) {
                console.log("   Already configured, skipping.");
                return;
            }
        } catch {
            // If read fails, continue with configuration
        }

        // Try to configure, skip if already configured
        try settlerContract.setOriginChainConfig(
            originChainId,
            origin.hyperlaneOracle,
            origin.depositEntrypoint
        ) {
            console.log("   Origin Chain ID:", originChainId);
            console.log("   Origin Oracle:", origin.hyperlaneOracle);
            console.log("   Origin DepositEntrypoint:", origin.depositEntrypoint);
        } catch {
            console.log("   Already configured or failed, skipping.");
        }
    }

    function _configureEntrypoint(
        address entrypoint,
        address poolHyperlaneOracle,
        ChainConfig.OriginConfig memory originConfig,
        OriginAddresses memory origin
    ) internal {
        console.log("2. Configuring Entrypoint for withdrawals...");

        ShinobiCashEntrypoint entrypointContract = ShinobiCashEntrypoint(payable(entrypoint));

        // Check if already configured
        (bool isConfigured,,,,,) = entrypointContract.withdrawalChainConfig(originConfig.chainId);
        if (isConfigured) {
            console.log("   Already configured, skipping.");
            return;
        }

        entrypointContract.setWithdrawalChainConfig(
            originConfig.chainId,
            origin.withdrawalOutputSettler,
            origin.hyperlaneOracle,
            poolHyperlaneOracle,
            originConfig.fillDeadline,
            originConfig.expiry
        );
        console.log("   Destination Chain ID:", originConfig.chainId);
        console.log("   WithdrawalOutputSettler:", origin.withdrawalOutputSettler);
        console.log("   Fill Deadline:", originConfig.fillDeadline, "seconds");
        console.log("   Expiry:", originConfig.expiry, "seconds");
    }

    function _sanitizeChainName(string memory name) internal pure returns (string memory) {
        bytes memory b = bytes(name);
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            if (char == 0x20) result[i] = 0x2d;
            else if (uint8(char) >= 65 && uint8(char) <= 90) result[i] = bytes1(uint8(char) + 32);
            else result[i] = char;
        }
        return string(result);
    }
}
