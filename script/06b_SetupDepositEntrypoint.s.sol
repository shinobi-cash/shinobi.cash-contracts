// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Deposit Entrypoint
import {ShinobiCrosschainDepositEntrypoint} from "../src/contracts/ShinobiCrosschainDepositEntrypoint.sol";

/**
 * @title 06b_SetupDepositEntrypoint
 * @notice Configure Deposit Entrypoint for L2 deposits
 * @dev Requires: DEPOSIT_ENTRYPOINT, INPUT_SETTLER, FILL_ORACLE, INTENT_ORACLE,
 *               DESTINATION_CHAIN_ID, DESTINATION_ENTRYPOINT, DESTINATION_ORACLE env vars
 */
contract SetupDepositEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address depositEntrypointAddr = vm.envAddress("SHINOBI_CASH_DEPOSITE_ENTRYPOINT_BASE_SEPOLIA");
        address inputSettler = vm.envAddress("INPUT_SETTLER_BASE_SEPOLIA");

        // Oracle configuration
        address fillOracle = vm.envAddress("FILL_ORACLE");
        address intentOracle = vm.envAddress("INTENT_ORACLE");

        // Destination configuration (mainnet where pool is)
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");
        address destinationEntrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 6b: Setup Deposit Entrypoint (L2) ===");
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

        // 4. Set Destination Configuration (chain, entrypoint, oracle)
        console.log("4. Setting Destination Configuration...");
        // Note: destinationOracle is the oracle address on the destination chain
        address destinationOracle = vm.envAddress("DESTINATION_ORACLE");
        depositEntrypoint.setDestinationConfig(
            destinationChainId,
            destinationEntrypoint,
            destinationOracle
        );
        console.log("   Destination Chain ID:", destinationChainId);
        console.log("   Destination Entrypoint:", destinationEntrypoint);
        console.log("   Destination Oracle:", destinationOracle);

        // 5. Set default deadlines (optional, has defaults)
        console.log("5. Setting default deadlines...");
        depositEntrypoint.setDefaultFillDeadline(24 hours);
        depositEntrypoint.setDefaultExpiry(24 hours);
        console.log("   Fill Deadline: 24 hour");
        console.log("   Expiry: 24 hours");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deposit Entrypoint configuration complete ===");
        console.log("Users on this chain can now deposit to mainnet pool");
    }
}
