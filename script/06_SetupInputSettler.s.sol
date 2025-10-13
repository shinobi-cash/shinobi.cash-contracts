// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/contracts/ShinobiInputSettler.sol";

/**
 * @title 06_SetupInputSettler
 * @notice Configure Input Settler with entrypoint
 * @dev Requires: INPUT_SETTLER, ENTRYPOINT env vars
 */
contract SetupInputSettler is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address inputSettlerAddr = vm.envAddress("INPUT_SETTLER_BASE_SEPOLIA");
        address entrypoint = vm.envAddress("SHINOBI_CASH_DEPOSITE_ENTRYPOINT_BASE_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 6: Setup Input Settler ===");
        console.log("Deployer:", deployer);
        console.log("Input Settler:", inputSettlerAddr);
        console.log("Entrypoint:", entrypoint);
        console.log("");

        ShinobiInputSettler inputSettler = ShinobiInputSettler(payable(inputSettlerAddr));

        // Set entrypoint (only address allowed to call open())
        console.log("Setting entrypoint...");
        inputSettler.setEntrypoint(entrypoint);
        console.log("Entrypoint configured");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Input Settler configuration complete ===");
    }
}
