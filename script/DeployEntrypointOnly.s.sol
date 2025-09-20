// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ShinobiCashEntrypoint} from "../src/contracts/ShinobiCashEntrypoint.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployEntrypointOnly
 * @notice Deploy only the ShinobiCashEntrypoint contract
 */
contract DeployEntrypointOnly is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying ShinobiCashEntrypoint ===");
        console.log("Deployer:", deployer);

        // Deploy implementation
        ShinobiCashEntrypoint implementation = new ShinobiCashEntrypoint();
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature("initialize(address,address)", deployer, deployer)
        );
        
        address entrypoint = address(proxy);

        vm.stopBroadcast();

        console.log("Implementation:", address(implementation));
        console.log("Entrypoint (Proxy):", entrypoint);
        
        return entrypoint;
    }
}