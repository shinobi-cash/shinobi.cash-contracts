// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/contracts/ShinobiInputSettler.sol";

/**
 * @title 06_SetupInputSettler
 * @notice Verify Input Settler configuration (entrypoint set in constructor)
 * @dev NOTE: This script is now deprecated - entrypoint is set immutably in constructor
 * @dev Kept for verification purposes only
 */
contract SetupInputSettler is Script {
    function run() external view {
        // Get addresses from previous deployments
        address inputSettlerAddr = vm.envAddress("INPUT_SETTLER_ARBITRUM_SEPOLIA");
        address expectedEntrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");

        console.log("=== Step 6: Verify Input Settler Configuration ===");
        console.log("Input Settler:", inputSettlerAddr);
        console.log("Expected Entrypoint:", expectedEntrypoint);
        console.log("");

        ShinobiInputSettler inputSettler = ShinobiInputSettler(payable(inputSettlerAddr));

        // Verify entrypoint is correctly set (immutable from constructor)
        address actualEntrypoint = inputSettler.entrypoint();
        console.log("Actual Entrypoint:", actualEntrypoint);

        require(actualEntrypoint == expectedEntrypoint, "Entrypoint mismatch!");
        console.log("Entrypoint verification: PASSED");

        console.log("");
        console.log("=== Input Settler verified successfully ===");
        console.log("NOTE: Entrypoint is immutable and was set during deployment");
    }
}
