// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {IPoolDiamond} from "../../src/diamond/interfaces/IPoolDiamond.sol";

/**
 * @title DeployDiamond_03_Setup
 * @notice Configure the PoolDiamond via AdminFacet
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/diamond/DeployDiamond_03_Setup.s.sol:DeployDiamond_03_Setup \
 *     --rpc-url arbitrum-sepolia --broadcast
 */
contract DeployDiamond_03_Setup is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Read deployed addresses
        address diamondAddr = DeploymentWriter.readContractAddress(poolKey, "contracts", "poolDiamond");
        address inputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "inputSettler");
        address depositOutputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "depositOutputSettler");

        require(diamondAddr != address(0), "PoolDiamond not deployed");
        require(inputSettler != address(0), "InputSettler not deployed");
        require(depositOutputSettler != address(0), "DepositOutputSettler not deployed");

        console.log("==========================================================");
        console.log("  DIAMOND DEPLOYMENT - Step 3: Setup");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("Diamond:", diamondAddr);
        console.log("");

        IPoolDiamond diamond = IPoolDiamond(diamondAddr);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Set asset config
        console.log("1. Setting asset config...");
        try diamond.setAssetConfig(
            poolConfig.minimumDeposit,
            poolConfig.vettingFeeBPS,
            poolConfig.maxRelayFeeBPS
        ) {
            console.log("   Min Deposit:", poolConfig.minimumDeposit, "wei");
            console.log("   Vetting Fee:", poolConfig.vettingFeeBPS, "BPS");
            console.log("   Max Relay Fee:", poolConfig.maxRelayFeeBPS, "BPS");
        } catch {
            console.log("   Already set, skipping.");
        }

        // 2. Set max solver fee BPS
        console.log("2. Setting max solver fee BPS...");
        try diamond.setMaxSolverFeeBPS(poolConfig.maxSolverFeeBPS) {
            console.log("   Max Solver Fee:", poolConfig.maxSolverFeeBPS, "BPS");
        } catch {
            console.log("   Already set, skipping.");
        }

        // 3. Set withdrawal input settler
        console.log("3. Setting withdrawal input settler...");
        try diamond.setWithdrawalInputSettler(inputSettler) {
            console.log("   Set to:", inputSettler);
        } catch {
            console.log("   Already set, skipping.");
        }

        // 4. Set deposit output settler
        console.log("4. Setting deposit output settler...");
        try diamond.setDepositOutputSettler(depositOutputSettler) {
            console.log("   Set to:", depositOutputSettler);
        } catch {
            console.log("   Already set, skipping.");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  DIAMOND SETUP COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployDiamond_04_Paymasters.s.sol ...", poolKey);
    }
}
