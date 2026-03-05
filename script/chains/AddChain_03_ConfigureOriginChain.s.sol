// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

// Contracts to configure
import {ShinobiCrosschainDepositEntrypoint} from "../../src/crosschain/ShinobiCrosschainDepositEntrypoint.sol";
import {IHyperlaneOracle} from "../../src/oif/interfaces/IHyperlaneOracle.sol";

/**
 * @title AddChain_03_ConfigureOriginChain
 * @notice Configure the deposit entrypoint on the new origin chain
 * @dev Run this script on the NEW origin chain
 *
 * Input:  config/origins/{ORIGIN_KEY}.json
 * Reads:  deployments/{pool-key}.json, deployments/{origin-name}.json
 *
 * Usage:
 *   ORIGIN_KEY=base-sepolia forge script script/chains/AddChain_03_ConfigureOriginChain.s.sol --rpc-url base-sepolia --broadcast
 */
contract AddChain_03_ConfigureOriginChain is Script {
    struct PoolAddresses {
        address poolDiamond;
        address depositOutputSettler;
        address hyperlaneOracle;
    }

    struct OriginAddresses {
        address depositEntrypoint;
        address inputSettler;
        address hyperlaneOracle;
    }

    function run() external {
        string memory originKey = vm.envString("ORIGIN_KEY");

        // Load configurations
        ChainConfig.OriginConfig memory originConfig = ChainConfig.getOriginConfig(originKey);
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(originConfig.poolKey);

        require(block.chainid == originConfig.chainId, "Must run on origin chain!");

        string memory poolChainName = _sanitizeChainName(poolConfig.name);
        string memory originChainName = _sanitizeChainName(originConfig.name);

        PoolAddresses memory pool = _readPoolAddresses(poolChainName);
        OriginAddresses memory origin = _readOriginAddresses(originChainName);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  ADD NEW CHAIN - Step 3: Configure Origin Chain");
        console.log("==========================================================");
        console.log("");
        console.log("Origin Key:", originKey);
        console.log("Origin Chain:", originConfig.name);
        console.log("Pool Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        ShinobiCrosschainDepositEntrypoint entrypoint = ShinobiCrosschainDepositEntrypoint(
            payable(origin.depositEntrypoint)
        );

        _configureSettlerAndOracles(entrypoint, origin, pool);
        _configureDestination(entrypoint, poolConfig.chainId, pool);
        _configureDeadlinesAndFees(entrypoint, originConfig);
        _configureAssetPool(entrypoint, pool.poolDiamond);
        _configureHyperlane(entrypoint, origin.hyperlaneOracle, poolConfig.hyperlaneDomainId, pool.hyperlaneOracle);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  ORIGIN CHAIN CONFIGURATION COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Chain", originConfig.name, "is now fully configured!");
    }

    function _readPoolAddresses(string memory chainName) internal view returns (PoolAddresses memory) {
        PoolAddresses memory pool;
        pool.poolDiamond = DeploymentWriter.readContractAddress(chainName, "contracts", "poolDiamond");
        pool.depositOutputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "depositOutputSettler");
        pool.hyperlaneOracle = DeploymentWriter.readContractAddress(chainName, "contracts", "hyperlaneOracle");

        require(pool.poolDiamond != address(0), "PoolDiamond not deployed");
        require(pool.depositOutputSettler != address(0), "Pool DepositOutputSettler not deployed");
        require(pool.hyperlaneOracle != address(0), "Pool HyperlaneOracle not deployed");

        return pool;
    }

    function _readOriginAddresses(string memory chainName) internal view returns (OriginAddresses memory) {
        OriginAddresses memory origin;
        origin.depositEntrypoint = DeploymentWriter.readContractAddress(chainName, "contracts", "depositEntrypoint");
        origin.inputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "inputSettler");
        origin.hyperlaneOracle = DeploymentWriter.readContractAddress(chainName, "contracts", "hyperlaneOracle");

        require(origin.depositEntrypoint != address(0), "Origin DepositEntrypoint not deployed");
        require(origin.inputSettler != address(0), "Origin InputSettler not deployed");
        require(origin.hyperlaneOracle != address(0), "Origin HyperlaneOracle not deployed");

        return origin;
    }

    function _configureSettlerAndOracles(
        ShinobiCrosschainDepositEntrypoint entrypoint,
        OriginAddresses memory origin,
        PoolAddresses memory pool
    ) internal {
        console.log("1. Setting Input Settler...");
        if (entrypoint.inputSettler() == origin.inputSettler) {
            console.log("   Already set, skipping.");
        } else {
            entrypoint.setInputSettler(origin.inputSettler);
            console.log("   Set to:", origin.inputSettler);
        }

        console.log("2. Setting Fill Oracle...");
        if (entrypoint.fillOracle() == origin.hyperlaneOracle) {
            console.log("   Already set, skipping.");
        } else {
            entrypoint.setFillOracle(origin.hyperlaneOracle);
            console.log("   Set to:", origin.hyperlaneOracle);
        }

        console.log("3. Setting Intent Oracle...");
        if (entrypoint.intentOracle() == pool.hyperlaneOracle) {
            console.log("   Already set, skipping.");
        } else {
            entrypoint.setIntentOracle(pool.hyperlaneOracle);
            console.log("   Set to:", pool.hyperlaneOracle);
        }
    }

    function _configureDestination(
        ShinobiCrosschainDepositEntrypoint entrypoint,
        uint256 poolChainId,
        PoolAddresses memory pool
    ) internal {
        console.log("4. Setting Destination Configuration...");
        if (entrypoint.destinationChainId() == poolChainId &&
            entrypoint.destinationEntrypoint() == pool.poolDiamond &&
            entrypoint.destinationOutputSettler() == pool.depositOutputSettler &&
            entrypoint.destinationOracle() == pool.hyperlaneOracle) {
            console.log("   Already configured, skipping.");
        } else {
            entrypoint.setDestinationConfig(
                poolChainId,
                pool.poolDiamond,
                pool.depositOutputSettler,
                pool.hyperlaneOracle
            );
            console.log("   Destination Chain ID:", poolChainId);
            console.log("   Pool Diamond:", pool.poolDiamond);
            console.log("   Pool DepositOutputSettler:", pool.depositOutputSettler);
        }
    }

    function _configureDeadlinesAndFees(
        ShinobiCrosschainDepositEntrypoint entrypoint,
        ChainConfig.OriginConfig memory originConfig
    ) internal {
        console.log("5. Setting Deadlines...");
        if (
            entrypoint.defaultFillDeadline() == originConfig.fillDeadline
                && entrypoint.defaultExpiry() == originConfig.expiry
        ) {
            console.log("   Deadlines already set, skipping.");
        } else {
            entrypoint.setDefaultDeadlines(originConfig.fillDeadline, originConfig.expiry);
            console.log("   Fill Deadline:", originConfig.fillDeadline, "seconds");
            console.log("   Expiry:", originConfig.expiry, "seconds");
        }

        console.log("6. Setting Fee Configuration...");
        if (entrypoint.minimumDepositAmount() == originConfig.minimumDepositAmount) {
            console.log("   Minimum Deposit already set, skipping.");
        } else {
            entrypoint.setMinimumDepositAmount(originConfig.minimumDepositAmount);
            console.log("   Minimum Deposit:", originConfig.minimumDepositAmount, "wei");
        }

        if (entrypoint.maxSolverFeeBPS() == originConfig.maxSolverFeeBPS) {
            console.log("   Max Solver Fee already set, skipping.");
        } else {
            entrypoint.setMaxSolverFeeBPS(originConfig.maxSolverFeeBPS);
            console.log("   Max Solver Fee:", originConfig.maxSolverFeeBPS, "BPS");
        }

        if (entrypoint.defaultSolverFeeBPS() == originConfig.defaultSolverFeeBPS) {
            console.log("   Default Solver Fee already set, skipping.");
        } else {
            entrypoint.setDefaultSolverFeeBPS(originConfig.defaultSolverFeeBPS);
            console.log("   Default Solver Fee:", originConfig.defaultSolverFeeBPS, "BPS");
        }
    }

    function _configureAssetPool(
        ShinobiCrosschainDepositEntrypoint entrypoint,
        address poolEthPool
    ) internal {
        console.log("7. Setting Asset Pool Mapping...");
        if (entrypoint.assetToPool(Constants.NATIVE_ASSET) == poolEthPool) {
            console.log("   Already configured, skipping.");
        } else {
            entrypoint.setAssetPool(Constants.NATIVE_ASSET, poolEthPool);
            console.log("   ETH Pool:", poolEthPool);
        }
    }

    function _configureHyperlane(
        ShinobiCrosschainDepositEntrypoint entrypoint,
        address originHyperlaneOracle,
        uint32 poolDomainId,
        address poolHyperlaneOracle
    ) internal {
        console.log("8. Configuring Hyperlane...");
        uint256 hyperlaneGasLimit = 200_000;

        // Try to read current config, configure if different or read fails
        bool needsConfig = true;
        try entrypoint.hyperlaneOracle() returns (IHyperlaneOracle currentOracle) {
            if (address(currentOracle) == originHyperlaneOracle &&
                entrypoint.destinationHyperlaneDomain() == poolDomainId &&
                entrypoint.destinationHyperlaneOracle() == poolHyperlaneOracle &&
                entrypoint.hyperlaneGasLimit() == hyperlaneGasLimit) {
                needsConfig = false;
                console.log("   Already configured, skipping.");
            }
        } catch {
            // Read failed, need to configure
        }

        if (needsConfig) {
            try entrypoint.setHyperlaneConfig(
                originHyperlaneOracle,
                poolDomainId,
                poolHyperlaneOracle,
                hyperlaneGasLimit
            ) {
                console.log("   Origin Oracle:", originHyperlaneOracle);
                console.log("   Destination Domain ID:", poolDomainId);
                console.log("   Pool Oracle:", poolHyperlaneOracle);
                console.log("   Gas Limit:", hyperlaneGasLimit);
            } catch {
                console.log("   Function not available on deployed contract, skipping.");
            }
        }
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
