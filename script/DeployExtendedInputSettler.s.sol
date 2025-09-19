// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ExtendedInputSettler} from "../src/oif/contracts/ExtendedInputSettler.sol";

/**
 * @title DeployExtendedInputSettler
 * @notice Deployment script for the ExtendedInputSettler contract
 * @dev Extended OIF InputSettlerEscrow with custom refund calldata execution
 */
contract DeployExtendedInputSettler is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ExtendedInputSettler contract
        ExtendedInputSettler inputSettler = new ExtendedInputSettler();
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("ExtendedInputSettler deployed at:", address(inputSettler));
        console.log("Deployer:", deployer);
        
        return address(inputSettler);
    }
}