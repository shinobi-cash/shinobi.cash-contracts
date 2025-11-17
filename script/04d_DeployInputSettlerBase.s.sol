// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/ShinobiInputSettler.sol";

/**
 * @title 04d_DeployInputSettlerBase
 * @notice Deploy Shinobi Input Settler on Base Sepolia (User Chain)
 * @dev This script deploys the Input Settler for the USER CHAIN (Base Sepolia):
 *      - Input Settler (for deposit intents originating from Base → Arbitrum)
 *
 * @dev Required env vars (Base Sepolia):
 *      - SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA: Deposit entrypoint address for Input Settler
 *
 * @dev Architecture:
 *      Base Sepolia (User Chain):
 *      ├── ShinobiCrosschainDepositEntrypoint (deposits originate here)
 *      └── ShinobiInputSettler (escrows funds for deposit intents) ← THIS SCRIPT
 */
contract DeployInputSettlerBase is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required address for Base Sepolia
        address depositEntrypoint = vm.envAddress("SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4d: Deploy Input Settler (Base Sepolia - User Chain) ===");
        console.log("Deployer:", deployer);
        console.log("Deposit Entrypoint:", depositEntrypoint);
        console.log("");

        // Deploy Input Settler (for deposit intents originating on Base)
        console.log("Deploying Input Settler...");
        address inputSettler = address(new ShinobiInputSettler(depositEntrypoint));
        console.log("   Shinobi Input Settler:", inputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Input Settler Deployment Complete (Base Sepolia) ===");
        console.log("");
        console.log("Save this address:");
        console.log("INPUT_SETTLER_BASE_SEPOLIA=", inputSettler);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("Configure this settler in step 06b (ShinobiCrosschainDepositEntrypoint)");
    }
}
