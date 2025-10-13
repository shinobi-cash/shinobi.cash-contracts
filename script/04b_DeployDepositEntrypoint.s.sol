// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Deposit Entrypoint
import {ShinobiCrosschainDepositEntrypoint} from "../src/contracts/ShinobiCrosschainDepositEntrypoint.sol";

/**
 * @title 04b_DeployDepositEntrypoint
 * @notice Deploy Deposit Entrypoint for L2 chains
 * @dev This should be deployed on L2 chains (e.g., Arbitrum) for deposits
 * @dev The main ShinobiCashEntrypoint (step 02) is for withdrawals on mainnet
 */
contract DeployDepositEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4b: Deploy Deposit Entrypoint (for L2) ===");
        console.log("Deployer:", deployer);
        console.log("");

        address depositEntrypoint = address(new ShinobiCrosschainDepositEntrypoint(deployer));

        console.log("Deposit Entrypoint:", depositEntrypoint);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save this address for configuration ===");
        console.log("NOTE: This needs to be configured in step 06b with:");
        console.log("  - Input Settler address");
        console.log("  - Oracle addresses (fillOracle, intentOracle)");
        console.log("  - Destination chain ID and entrypoint");
    }
}
