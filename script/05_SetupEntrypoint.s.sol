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
 * @notice Configure Shinobi Cash Entrypoint with pool and settlers
 * @dev Requires: ENTRYPOINT, ETH_POOL, INPUT_SETTLER, OUTPUT_SETTLER env vars
 */
contract SetupEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address entrypointAddr = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address ethPool = vm.envAddress("SHINOBI_CASH_ETH_POOL");
        address inputSettler = vm.envAddress("INPUT_SETTLER_ARBITRUM_SEPOLIA");
        address outputSettler = vm.envAddress("OUTPUT_SETTLER_ARBITRUM_SEPOLIA");

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

        // 2. Set Input Settler
        console.log("2. Setting Input Settler...");
        entrypoint.setInputSettler(inputSettler);
        console.log("   Input Settler set:", inputSettler);

        // 3. Set Output Settler
        console.log("3. Setting Output Settler...");
        entrypoint.setOutputSettler(outputSettler);
        console.log("   Output Settler set:", outputSettler);

        // 4. Enable supported chains
        console.log("4. Enabling cross-chain support...");
        entrypoint.updateChainSupport(84532, true);  // Base Sepolia
        console.log("   Enabled chains: Base Sepolia (84532)");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Entrypoint configuration complete ===");
    }
}
