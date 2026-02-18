// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {ShinobiCashEntrypoint} from "../../src/core/ShinobiCashEntrypoint.sol";

/**
 * @title Pool_07_UpgradeEntrypoint
 * @notice Upgrade ShinobiCashEntrypoint implementation
 * @dev Deploys new implementation and upgrades the proxy
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Reads:  deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/Pool_07_UpgradeEntrypoint.s.sol:Pool_07_UpgradeEntrypoint --rpc-url arbitrum-sepolia --broadcast
 */
contract Pool_07_UpgradeEntrypoint is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        // Read proxy address from deployment file
        address entrypointProxy = DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint");
        require(entrypointProxy != address(0), "Entrypoint proxy not found in deployment file");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get current implementation
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImpl = address(uint160(uint256(vm.load(entrypointProxy, implSlot))));

        console.log("==========================================================");
        console.log("  ENTRYPOINT UPGRADE - Step 7");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Proxy Address:", entrypointProxy);
        console.log("Current Implementation:", currentImpl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new implementation
        console.log("1. Deploying new ShinobiCashEntrypoint implementation...");
        ShinobiCashEntrypoint newImpl = new ShinobiCashEntrypoint();
        console.log("   New Implementation:", address(newImpl));

        // 2. Upgrade proxy to new implementation
        console.log("2. Upgrading proxy to new implementation...");
        ShinobiCashEntrypoint(payable(entrypointProxy)).upgradeToAndCall(
            address(newImpl),
            "" // No initialization data needed for upgrade
        );
        console.log("   Upgrade complete!");

        vm.stopBroadcast();

        // Verify upgrade
        address newImplAfterUpgrade = address(uint160(uint256(vm.load(entrypointProxy, implSlot))));

        console.log("");
        console.log("==========================================================");
        console.log("  UPGRADE COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Previous Implementation:", currentImpl);
        console.log("New Implementation:", address(newImpl));
        console.log("Verified Implementation:", newImplAfterUpgrade);
        console.log("");

        if (newImplAfterUpgrade == address(newImpl)) {
            console.log("SUCCESS: Proxy now points to new implementation");
        } else {
            console.log("WARNING: Implementation address mismatch!");
        }
    }
}
