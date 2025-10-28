// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Deposit Entrypoint
import {ShinobiCrosschainDepositEntrypoint} from "../src/core/ShinobiCrosschainDepositEntrypoint.sol";

/**
 * @title 06_SetupDepositEntrypoint
 * @notice Configure Deposit Entrypoint for L2 deposits (Base Sepolia -> Arbitrum Sepolia)
 * @dev Required env vars:
 *      - SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA: Deposit entrypoint on Base Sepolia
 *      - INPUT_SETTLER_BASE_SEPOLIA: Input settler on Base Sepolia
 *      - FILL_ORACLE_BASE_SEPOLIA: Oracle on Base Sepolia (validates fills on Arbitrum)
 *      - INTENT_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum Sepolia (validates intents from Base)
 *      - DESTINATION_CHAIN_ID: 421614 (Arbitrum Sepolia)
 *      - SHINOBI_CASH_ENTRYPOINT_PROXY: Main entrypoint on Arbitrum Sepolia
 *      - DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA: Output settler on Arbitrum Sepolia
 *      - DESTINATION_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum Sepolia (validates outputs)
 */
contract SetupDepositEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address depositEntrypointAddr = vm.envAddress("SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA");
        address inputSettler = vm.envAddress("INPUT_SETTLER_BASE_SEPOLIA");

        // Oracle configuration
        // CRITICAL: For cross-chain deposits from Base Sepolia -> Arbitrum Sepolia:
        // - fillOracle: Base Sepolia oracle (validates fills happened on Arbitrum)
        // - intentOracle: Arbitrum Sepolia oracle (validates intent came from Base)
        // - destinationOracle: Arbitrum Sepolia oracle (validates output on Arbitrum)
        address fillOracle = vm.envAddress("FILL_ORACLE_BASE_SEPOLIA");  // Base Sepolia oracle
        address intentOracle = vm.envAddress("INTENT_ORACLE_ARBITRUM_SEPOLIA");  // Arbitrum Sepolia oracle

        // Destination configuration (Arbitrum Sepolia where pool is)
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");
        address destinationEntrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address destinationOutputSettler = vm.envAddress("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA");
        address destinationOracle = vm.envAddress("DESTINATION_ORACLE_ARBITRUM_SEPOLIA");  // Arbitrum Sepolia oracle

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 6: Setup Deposit Entrypoint (L2) ===");
        console.log("Deployer:", deployer);
        console.log("Deposit Entrypoint:", depositEntrypointAddr);
        console.log("");

        ShinobiCrosschainDepositEntrypoint depositEntrypoint =
            ShinobiCrosschainDepositEntrypoint(payable(depositEntrypointAddr));

        // 1. Set Input Settler
        console.log("1. Setting Input Settler...");
        depositEntrypoint.setInputSettler(inputSettler);
        console.log("   Input Settler set:", inputSettler);

        // 2. Set Fill Oracle (validates fills on destination)
        console.log("2. Setting Fill Oracle...");
        depositEntrypoint.setFillOracle(fillOracle);
        console.log("   Fill Oracle set:", fillOracle);

        // 3. Set Intent Oracle (validates intents from origin)
        console.log("3. Setting Intent Oracle...");
        depositEntrypoint.setIntentOracle(intentOracle);
        console.log("   Intent Oracle set:", intentOracle);

        // 4. Set Destination Configuration (chain, entrypoint, output settler, oracle)
        console.log("4. Setting Destination Configuration...");
        // Note: destinationOracle is the oracle address on the destination chain
        depositEntrypoint.setDestinationConfig(
            destinationChainId,
            destinationEntrypoint,
            destinationOutputSettler,
            destinationOracle
        );
        console.log("   Destination Chain ID:", destinationChainId);
        console.log("   Destination Entrypoint:", destinationEntrypoint);
        console.log("   Destination Output Settler:", destinationOutputSettler);
        console.log("   Destination Oracle:", destinationOracle);

        // 5. Set default deadlines (optional, has defaults)
        console.log("5. Setting default deadlines...");
        depositEntrypoint.setDefaultFillDeadline(23 hours);
        depositEntrypoint.setDefaultExpiry(24 hours);
        console.log("   Fill Deadline: 23 hour");
        console.log("   Expiry: 24 hours");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deposit Entrypoint configuration complete ===");
        console.log("Users on Base Sepolia can now deposit to Arbitrum Sepolia pool");
    }
}
