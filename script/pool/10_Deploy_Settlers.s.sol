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
 * @title Deploy_Settlers
 * @notice Deploy InputSettler, HyperlaneOracle, and DepositOutputSettler
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (shinobiPool)
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/10_Deploy_Settlers.s.sol:Deploy_Settlers --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_Settlers is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 10: Settlers & Oracle");
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

        // Check if all already deployed (verify on-chain code to avoid simulation-pass false positives)
        if (existingOracle != address(0) && existingOracle.code.length > 0 &&
            existingInputSettler != address(0) && existingInputSettler.code.length > 0 &&
            existingDepositOutputSettler != address(0) && existingDepositOutputSettler.code.length > 0) {
            console.log("All settlers already deployed:");
            console.log("  hyperlaneOracle:", existingOracle);
            console.log("  inputSettler:", existingInputSettler);
            console.log("  depositOutputSettler:", existingDepositOutputSettler);
            console.log("");
            console.log("Skipping deployment.");
            return;
        }

        // Read ShinobiPool from previous deployment
        address shinobiPool = DeploymentWriter.readContractAddress(poolKey, "contracts", "shinobiPool");
        require(shinobiPool != address(0), "ShinobiPool not deployed. Run Step 9 first.");

        console.log("ShinobiPool:", shinobiPool);
        console.log("Hyperlane Mailbox:", poolConfig.hyperlaneMailbox);
        console.log("");

        address oracleAddr = existingOracle;

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy HyperlaneOracle
        if (existingOracle != address(0) && existingOracle.code.length > 0) {
            console.log("1. HyperlaneOracle already deployed:", existingOracle);
        } else {
            console.log("1. Deploying HyperlaneOracle...");
            uint256 blockBefore = block.number;
            oracleAddr = address(new HyperlaneOracle(poolConfig.hyperlaneMailbox, address(0), address(0)));
            DeploymentWriter.writeContract(poolKey, "hyperlaneOracle", oracleAddr, blockBefore);
            console.log("   Address:", oracleAddr);
        }

        // 2. Deploy InputSettler
        if (existingInputSettler != address(0) && existingInputSettler.code.length > 0) {
            console.log("2. InputSettler already deployed:", existingInputSettler);
        } else {
            console.log("2. Deploying ShinobiInputSettler...");
            uint256 blockBefore = block.number;
            address addr = address(new ShinobiInputSettler(shinobiPool, deployer));
            DeploymentWriter.writeContract(poolKey, "inputSettler", addr, blockBefore);
            console.log("   Address:", addr);
        }

        // 3. Deploy DepositOutputSettler
        if (existingDepositOutputSettler != address(0) && existingDepositOutputSettler.code.length > 0) {
            console.log("3. DepositOutputSettler already deployed:", existingDepositOutputSettler);
        } else {
            console.log("3. Deploying ShinobiDepositOutputSettler...");
            uint256 blockBefore = block.number;
            address addr = address(new ShinobiDepositOutputSettler(deployer, oracleAddr));
            DeploymentWriter.writeContract(poolKey, "depositOutputSettler", addr, blockBefore);
            console.log("   Address:", addr);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  SETTLERS & ORACLE COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 11_Setup_ShinobiPool.s.sol ...", poolKey);
    }
}
