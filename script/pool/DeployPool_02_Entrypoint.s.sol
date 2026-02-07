// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Entrypoint
import {ShinobiCashEntrypoint} from "../../src/core/ShinobiCashEntrypoint.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPool_02_Entrypoint
 * @notice Deploy ShinobiCashEntrypoint (UUPS proxy) on pool chain (skips if deployed)
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_02_Entrypoint.s.sol:DeployPool_02_Entrypoint \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployPool_02_Entrypoint is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");
        require(DeploymentWriter.deploymentExists(poolKey), "Run Step 1 first");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  POOL DEPLOYMENT - Step 2: Entrypoint");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Check if already deployed
        address existingEntrypoint = DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint");

        if (existingEntrypoint != address(0)) {
            console.log("Entrypoint already deployed:", existingEntrypoint);
            console.log("");
            console.log("Skipping deployment. Delete from deployment file to redeploy.");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        console.log("1. Deploying ShinobiCashEntrypoint implementation...");
        uint256 blockBefore = block.number;
        ShinobiCashEntrypoint implementation = new ShinobiCashEntrypoint();
        DeploymentWriter.writeContract(poolKey, "entrypointImpl", address(implementation), blockBefore);
        console.log("   Address:", address(implementation));
        console.log("   Block:", blockBefore);

        // Deploy proxy
        console.log("2. Deploying ERC1967Proxy...");
        blockBefore = block.number;
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", deployer, deployer);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        DeploymentWriter.writeContract(poolKey, "entrypoint", address(proxy), blockBefore);
        console.log("   Address:", address(proxy));
        console.log("   Block:", blockBefore);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  ENTRYPOINT DEPLOYED");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployPool_03_PrivacyPool.s.sol ...", poolKey);
    }
}
