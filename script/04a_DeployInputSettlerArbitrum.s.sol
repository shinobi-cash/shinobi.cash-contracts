// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/ShinobiInputSettler.sol";

/**
 * @title 04a_DeployInputSettlerArbitrum
 * @notice Deploy Shinobi Input Settler on Arbitrum Sepolia (Pool Chain)
 * @dev This script deploys the Input Settler for the POOL CHAIN (Arbitrum Sepolia):
 *      - Input Settler (for withdrawal intents originating from this chain)
 *
 * @dev Required env vars (Arbitrum Sepolia):
 *      - SHINOBI_CASH_ENTRYPOINT_PROXY: Entrypoint address for Input Settler
 *
 * @dev Architecture:
 *      Arbitrum Sepolia (Pool Chain):
 *      ├── ShinobiCashEntrypoint (withdrawals originate here)
 *      └── ShinobiInputSettler (escrows funds for withdrawal intents) ← THIS SCRIPT
 */
contract DeployInputSettlerArbitrum is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required addresses for Arbitrum Sepolia
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4a: Deploy Input Settler (Arbitrum Sepolia - Pool Chain) ===");
        console.log("Deployer:", deployer);
        console.log("Entrypoint:", entrypoint);
        console.log("");

        // Deploy Input Settler (for withdrawal intents originating on Arbitrum)
        console.log("Deploying Input Settler...");
        address inputSettler = address(new ShinobiInputSettler(entrypoint));
        console.log("   Shinobi Input Settler:", inputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Input Settler Deployment Complete (Arbitrum Sepolia) ===");
        console.log("");
        console.log("Save this address:");
        console.log("INPUT_SETTLER_ARBITRUM_SEPOLIA=", inputSettler);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Deploy Deposit Output Settler using script 04b");
        console.log("2. Configure these settlers in step 05 (ShinobiCashEntrypoint)");
    }
}
