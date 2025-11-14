// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Deposit Entrypoint
import {ShinobiCrosschainDepositEntrypoint} from "../src/core/ShinobiCrosschainDepositEntrypoint.sol";

/**
 * @title 04b_DeployDepositEntrypoint
 * @notice Deploy Deposit Entrypoint on Base Sepolia (User Chain)
 * @dev This should be deployed on Base Sepolia for users to initiate cross-chain deposits
 * @dev The main ShinobiCashEntrypoint (step 02) is deployed on Arbitrum Sepolia (Pool Chain)
 * @dev Required env vars:
 *      - INPUT_SETTLER_BASE_SEPOLIA: Input settler address (immutable, set in constructor)
 */
contract DeployDepositEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get inputSettler address (required for immutable constructor parameter)
        address inputSettler = vm.envAddress("INPUT_SETTLER_BASE_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4c: Deploy Deposit Entrypoint (for L2) ===");
        console.log("Deployer:", deployer);
        console.log("Input Settler:", inputSettler);
        console.log("");

        // Deploy with immutable inputSettler
        address depositEntrypoint = address(new ShinobiCrosschainDepositEntrypoint(deployer));

        console.log("Deposit Entrypoint:", depositEntrypoint);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save this address for configuration ===");
        console.log("NOTE: This needs to be configured in step 06 with:");
        console.log("  - Oracle addresses (fillOracle, intentOracle)");
        console.log("  - Destination chain ID and entrypoint");
        console.log("  - Fee configuration (minimumDepositAmount, solverFeeBPS)");
    }
}
