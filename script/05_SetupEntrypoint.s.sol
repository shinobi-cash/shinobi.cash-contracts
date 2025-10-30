// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Shinobi Cash contracts
import {ShinobiCashEntrypoint} from "../src/core/ShinobiCashEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title 05_SetupEntrypoint
 * @notice Configure Shinobi Cash Entrypoint with pool, settlers, and supported chains
 * @dev Requires: ENTRYPOINT, ETH_POOL, WITHDRAWAL_INPUT_SETTLER, DEPOSIT_OUTPUT_SETTLER env vars
 * @dev Note: Intent oracle is NOT configured here - it's set immutably in ShinobiDepositOutputSettler constructor
 * @dev Withdrawal chain config requires: output settler, output oracle, fill oracle, deadlines
 */
contract SetupEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments - Arbitrum Sepolia (Pool Chain)
        address entrypointAddr = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address ethPool = vm.envAddress("SHINOBI_CASH_ETH_POOL");
        address withdrawalInputSettler = vm.envAddress("INPUT_SETTLER_ARBITRUM_SEPOLIA");
        address depositOutputSettler = vm.envAddress("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA");

        // Get addresses for Base Sepolia (Destination Chain for Withdrawals)
        address withdrawalOutputSettler = vm.envAddress("WITHDRAWAL_OUTPUT_SETTLER_BASE_SEPOLIA");
        address outputOracle = vm.envAddress("OUTPUT_ORACLE_BASE_SEPOLIA");
        // Fill oracle validates fills on ORIGIN chain (Arb Sepolia), not destination
        address fillOracle = vm.envAddress("FILL_ORACLE_ARBITRUM_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 5: Setup Entrypoint Configuration ===");
        console.log("Deployer:", deployer);
        console.log("Entrypoint:", entrypointAddr);
        console.log("");

        ShinobiCashEntrypoint entrypoint = ShinobiCashEntrypoint(payable(entrypointAddr));

        // 1. Register ETH Privacy Pool
        console.log("1. Registering ETH Privacy Pool...");
        entrypoint.registerPool(
            IERC20(Constants.NATIVE_ASSET), // ETH
            IPrivacyPool(ethPool),
            0.001 ether, // MIN_DEPOSIT (0.001 ETH)
            100, // VETTING_FEE_BPS (1%)
            1500 // MAX_RELAY_FEE_BPS (15%)
        );
        console.log("   ETH Pool registered:", ethPool);

        // 2. Set Withdrawal Input Settler (for withdrawal intents)
        console.log("2. Setting Withdrawal Input Settler...");
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        console.log("   Withdrawal Input Settler set:", withdrawalInputSettler);

        // 3. Set Deposit Output Settler (for receiving cross-chain deposits)
        console.log("3. Setting Deposit Output Settler...");
        entrypoint.setDepositOutputSettler(depositOutputSettler);
        console.log("   Deposit Output Settler set:", depositOutputSettler);

        // 4. Configure withdrawal destination chain (Base Sepolia)
        console.log("4. Configuring withdrawal chain (Base Sepolia)...");
        entrypoint.setWithdrawalChainConfig(
            84532, // Base Sepolia chain ID
            withdrawalOutputSettler, // Withdrawal Output Settler on Base
            outputOracle, // Output oracle on Base
            fillOracle, // Fill oracle for validating fills
            23 hours, // Fill deadline (solver must fill within 23 hour)
            24 hours // Expiry (intent expires after 24 hours)
        );
        console.log("   Configured chain: Base Sepolia (84532)");
        console.log("   - Withdrawal Output Settler:", withdrawalOutputSettler);
        console.log("   - Output Oracle:", outputOracle);
        console.log("   - Fill Oracle:", fillOracle);
        console.log("   - Fill Deadline: 23 hour");
        console.log("   - Expiry: 24 hours");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Entrypoint configuration complete ===");
        console.log("");
        console.log("Summary:");
        console.log("- ETH Pool: Registered with 0.001 ETH minimum deposit");
        console.log("- Withdrawal Input Settler: Configured");
        console.log("- Deposit Output Settler: Configured");
        console.log("- Cross-chain withdrawals: Enabled to Base Sepolia (84532)");
    }
}
