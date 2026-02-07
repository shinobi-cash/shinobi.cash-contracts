// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Mock Oracle
import {MockOracle} from "../src/mocks/MockOracle.sol";

/**
 * @title 00_DeployMockOracles
 * @notice Deploy mock oracles for testing
 * @dev WARNING: These oracles bypass all validation - ONLY for testing!
 * @dev For production, deploy real OIF oracles (Direct/Hyperlane)
 */
contract DeployMockOracles is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 0: Deploy Mock Oracles (TESTING ONLY) ===");
        console.log("WARNING: These oracles bypass ALL validation");
        console.log("Deployer:", deployer);
        console.log("");

        // Deploy mock oracles
        // In production, you would deploy separate Direct and Hyperlane oracles
        // For testing, we use the same mock oracle for all roles
        address fillOracle = address(new MockOracle());
        address intentOracle = address(new MockOracle());

        console.log("Mock Fill Oracle:", fillOracle);
        console.log("Mock Intent Oracle:", intentOracle);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Mock Oracles Deployed ===");
        console.log("Use these for FILL_ORACLE and INTENT_ORACLE");
        console.log("");
        console.log("IMPORTANT NOTES:");
        console.log("1. These oracles allow ANY intent/fill to pass validation");
        console.log("2. Use only for local testing or testnets");
        console.log("3. For production, deploy real OIF oracles:");
        console.log("   - DirectOracle for withdrawals");
        console.log("   - HyperlaneOracle for deposits");
    }
}
