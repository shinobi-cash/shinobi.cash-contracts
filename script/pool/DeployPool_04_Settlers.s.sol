// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Settlers and Oracle
import {ShinobiInputSettler} from "../../src/oif/ShinobiInputSettler.sol";
import {ShinobiDepositOutputSettler} from "../../src/oif/ShinobiDepositOutputSettler.sol";
import {HyperlaneOracle} from "../../src/oif/hyperlane/HyperlaneOracle.sol";

/**
 * @title DeployPool_04_Settlers
 * @notice Deploy InputSettler, HyperlaneOracle, and DepositOutputSettler - skips if deployed
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_04_Settlers.s.sol:DeployPool_04_Settlers \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployPool_04_Settlers is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  POOL DEPLOYMENT - Step 4: Settlers & Oracle");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Check existing deployments
        address existingOracle = DeploymentWriter.readContractAddress(poolKey, "contracts", "hyperlaneOracle");
        address existingInputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "inputSettler");
        address existingDepositOutputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "depositOutputSettler");

        // Check if all already deployed
        if (existingOracle != address(0) &&
            existingInputSettler != address(0) &&
            existingDepositOutputSettler != address(0)) {
            console.log("All settlers already deployed:");
            console.log("  hyperlaneOracle:", existingOracle);
            console.log("  inputSettler:", existingInputSettler);
            console.log("  depositOutputSettler:", existingDepositOutputSettler);
            console.log("");
            console.log("Skipping deployment.");
            return;
        }

        // Read entrypoint from previous deployment
        address entrypoint = DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint");
        require(entrypoint != address(0), "Entrypoint not deployed. Run Step 2 first.");

        console.log("Entrypoint:", entrypoint);
        console.log("Hyperlane Mailbox:", poolConfig.hyperlaneMailbox);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy HyperlaneOracle
        address oracleAddr = existingOracle;
        if (existingOracle != address(0)) {
            console.log("1. HyperlaneOracle already deployed:", existingOracle);
        } else {
            console.log("1. Deploying HyperlaneOracle...");
            uint256 blockBefore = block.number;
            HyperlaneOracle oracle = new HyperlaneOracle(
                poolConfig.hyperlaneMailbox,
                address(0),
                address(0)
            );
            oracleAddr = address(oracle);
            DeploymentWriter.writeContract(poolKey, "hyperlaneOracle", oracleAddr, blockBefore);
            console.log("   Address:", oracleAddr);
            console.log("   Block:", blockBefore);
        }

        // 2. Deploy InputSettler
        if (existingInputSettler != address(0)) {
            console.log("2. InputSettler already deployed:", existingInputSettler);
        } else {
            console.log("2. Deploying ShinobiInputSettler...");
            uint256 blockBefore = block.number;
            ShinobiInputSettler inputSettler = new ShinobiInputSettler(entrypoint);
            DeploymentWriter.writeContract(poolKey, "inputSettler", address(inputSettler), blockBefore);
            console.log("   Address:", address(inputSettler));
            console.log("   Block:", blockBefore);
        }

        // 3. Deploy DepositOutputSettler
        if (existingDepositOutputSettler != address(0)) {
            console.log("3. DepositOutputSettler already deployed:", existingDepositOutputSettler);
        } else {
            console.log("3. Deploying ShinobiDepositOutputSettler...");
            uint256 blockBefore = block.number;
            ShinobiDepositOutputSettler depositOutputSettler = new ShinobiDepositOutputSettler(
                deployer,
                oracleAddr
            );
            DeploymentWriter.writeContract(poolKey, "depositOutputSettler", address(depositOutputSettler), blockBefore);
            console.log("   Address:", address(depositOutputSettler));
            console.log("   Block:", blockBefore);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  SETTLERS & ORACLE COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployPool_05_Paymasters.s.sol ...", poolKey);
    }
}
