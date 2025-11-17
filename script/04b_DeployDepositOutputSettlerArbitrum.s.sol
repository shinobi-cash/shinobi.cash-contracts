// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiDepositOutputSettler} from "../src/oif/ShinobiDepositOutputSettler.sol";

/**
 * @title 04b_DeployDepositOutputSettlerArbitrum
 * @notice Deploy Deposit Output Settler on Arbitrum Sepolia (Pool Chain)
 * @dev This script deploys the Deposit Output Settler for receiving cross-chain deposits from Base
 *
 * @dev Required env vars (Arbitrum Sepolia):
 *      - INTENT_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum for deposit validation
 *
 * @dev Architecture:
 *      Arbitrum Sepolia (Pool Chain):
 *      ├── ShinobiCashEntrypoint (receives cross-chain deposits)
 *      └── ShinobiDepositOutputSettler (validates and fills deposit intents) ← THIS SCRIPT
 *
 *      Base Sepolia (User Chain):
 *      ├── ShinobiCrosschainDepositEntrypoint (deposits originate here)
 *      └── ShinobiInputSettler (escrows deposit funds)
 */
contract DeployDepositOutputSettlerArbitrum is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required addresses for Arbitrum Sepolia
        address intentOracle = vm.envAddress("INTENT_ORACLE_ARBITRUM_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4b: Deploy Deposit Output Settler (Arbitrum Sepolia - Pool Chain) ===");
        console.log("Deployer:", deployer);
        console.log("Intent Oracle:", intentOracle);
        console.log("");

        // Deploy Deposit Output Settler (for receiving deposits from Base Sepolia)
        console.log("Deploying Deposit Output Settler...");
        address depositOutputSettler = address(new ShinobiDepositOutputSettler(deployer, intentOracle));
        console.log("   Shinobi Deposit Output Settler:", depositOutputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deposit Output Settler Deployment Complete (Arbitrum Sepolia) ===");
        console.log("");
        console.log("Save this address:");
        console.log("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA=", depositOutputSettler);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("Configure this settler in step 05 (ShinobiCashEntrypoint)");
    }
}
