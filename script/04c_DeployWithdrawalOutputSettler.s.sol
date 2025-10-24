// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiWithdrawalOutputSettler} from "../src/oif/ShinobiWithdrawalOutputSettler.sol";

/**
 * @title 04c_DeployWithdrawalOutputSettler
 * @notice Deploy Withdrawal Output Settler on Base Sepolia (User Chain)
 * @dev This script deploys the Withdrawal Output Settler for receiving cross-chain withdrawals
 *      from Arbitrum Sepolia (Pool Chain) to Base Sepolia (User Chain)
 *
 * @dev ⚠️ IMPORTANT: This must be deployed on Base Sepolia (destination chain for withdrawals)
 *
 * @dev Required env vars (Base Sepolia):
 *      - FILL_ORACLE_BASE_SEPOLIA: Oracle on Base for withdrawal fill validation
 *
 * @dev Architecture:
 *      Arbitrum Sepolia (Pool Chain):
 *      ├── ShinobiCashEntrypoint (withdrawals originate here)
 *      └── ShinobiInputSettler (escrows funds for withdrawal intents)
 *
 *      Base Sepolia (User Chain):
 *      └── ShinobiWithdrawalOutputSettler (receives cross-chain withdrawals) ← THIS SCRIPT
 */
contract DeployWithdrawalOutputSettler is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required oracle address for Base Sepolia
        address fillOracle = vm.envAddress("FILL_ORACLE_BASE_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4c: Deploy Withdrawal Output Settler (Base Sepolia - User Chain) ===");
        console.log("Deployer:", deployer);
        console.log("Fill Oracle:", fillOracle);
        console.log("");

        // Deploy Withdrawal Output Settler (for receiving withdrawals from Arbitrum)
        console.log("Deploying Withdrawal Output Settler...");
        address withdrawalOutputSettler = address(new ShinobiWithdrawalOutputSettler(deployer, fillOracle));
        console.log("   Shinobi Withdrawal Output Settler:", withdrawalOutputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Withdrawal Output Settler Deployment Complete (Base Sepolia) ===");
        console.log("");
        console.log("Save this address:");
        console.log("WITHDRAWAL_OUTPUT_SETTLER_BASE_SEPOLIA=", withdrawalOutputSettler);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("This settler will be used when users receive withdrawals on Base Sepolia");
    }
}
