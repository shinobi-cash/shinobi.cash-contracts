// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/ShinobiInputSettler.sol";
import {ShinobiDepositOutputSettler} from "../src/oif/ShinobiDepositOutputSettler.sol";
import {ShinobiWithdrawalOutputSettler} from "../src/oif/ShinobiWithdrawalOutputSettler.sol";

/**
 * @title 04_DeployOIFSettlers
 * @notice Deploy Shinobi Input and Output Settlers for OIF protocol on Arbitrum Sepolia (Pool Chain)
 * @dev This script deploys settlers for the POOL CHAIN (Arbitrum Sepolia):
 *      - Input Settler (for withdrawal intents originating here)
 *      - Deposit Output Settler (for receiving cross-chain deposits from Base)
 *
 * @dev ⚠️ IMPORTANT: Withdrawal Output Settler is deployed separately on Base Sepolia (User Chain)
 *      Use script 04c_DeployWithdrawalOutputSettler.s.sol on Base Sepolia
 *
 * @dev Required env vars (Arbitrum Sepolia):
 *      - SHINOBI_CASH_ENTRYPOINT_PROXY: Entrypoint address for Input Settler
 *      - INTENT_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum for deposit validation
 *
 * @dev Deployment order (on Arbitrum Sepolia):
 *      1. ShinobiInputSettler (for withdrawal intents)
 *      2. ShinobiDepositOutputSettler (for receiving deposits)
 */
contract DeployOIFSettlers is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required addresses for Arbitrum Sepolia
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address intentOracle = vm.envAddress("INTENT_ORACLE_ARBITRUM_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4: Deploy OIF Settlers (Arbitrum Sepolia - Pool Chain) ===");
        console.log("Deployer:", deployer);
        console.log("Entrypoint:", entrypoint);
        console.log("Intent Oracle:", intentOracle);
        console.log("");

        // 1. Deploy Input Settler (for withdrawal intents originating on Arbitrum)
        console.log("1. Deploying Input Settler...");
        address inputSettler = address(new ShinobiInputSettler(entrypoint));
        console.log("   Shinobi Input Settler:", inputSettler);

        // 2. Deploy Deposit Output Settler (for receiving deposits from Base Sepolia)
        console.log("2. Deploying Deposit Output Settler...");
        address depositOutputSettler = address(new ShinobiDepositOutputSettler(deployer, intentOracle));
        console.log("   Shinobi Deposit Output Settler:", depositOutputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== OIF Settlers Deployment Complete (Arbitrum Sepolia) ===");
        console.log("");
        console.log("Save these addresses:");
        console.log("INPUT_SETTLER_ARBITRUM_SEPOLIA=", inputSettler);
        console.log("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA=", depositOutputSettler);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Deploy Withdrawal Output Settler on Base Sepolia using script 04c");
        console.log("2. Configure these settlers in step 05 (ShinobiCashEntrypoint)");
    }
}
