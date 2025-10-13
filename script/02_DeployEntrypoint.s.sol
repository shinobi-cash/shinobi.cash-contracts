// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Shinobi Cash contracts
import {ShinobiCashEntrypoint} from "../src/contracts/ShinobiCashEntrypoint.sol";

// OpenZeppelin proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title 02_DeployEntrypoint
 * @notice Deploy Shinobi Cash Entrypoint with UUPS proxy
 */
contract DeployEntrypoint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 2: Deploy Shinobi Cash Entrypoint ===");
        console.log("Deployer:", deployer);
        console.log("");

        // Deploy implementation
        address implementation = address(new ShinobiCashEntrypoint());
        console.log("Implementation:", implementation);

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(
            implementation,
            abi.encodeWithSignature("initialize(address,address)", deployer, deployer)
        ));
        console.log("Shinobi Cash Entrypoint (Proxy):", proxy);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save this address for next steps ===");
    }
}
