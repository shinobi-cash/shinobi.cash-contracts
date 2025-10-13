// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/contracts/ShinobiInputSettler.sol";
import {ShinobiOutputSettler} from "../src/oif/contracts/ShinobiOutputSettler.sol";

/**
 * @title 04_DeployOIFSettlers
 * @notice Deploy Shinobi Input and Output Settlers for OIF protocol
 */
contract DeployOIFSettlers is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4: Deploy OIF Settlers ===");
        console.log("Deployer:", deployer);
        console.log("");

        address inputSettler = address(new ShinobiInputSettler());
        address outputSettler = address(new ShinobiOutputSettler());

        console.log("Shinobi Input Settler:", inputSettler);
        console.log("Shinobi Output Settler:", outputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save these addresses for next steps ===");
        console.log("NOTE: These settlers need to be configured in step 05");
    }
}
