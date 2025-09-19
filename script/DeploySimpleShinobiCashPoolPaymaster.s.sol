// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/contracts/SimpleShinobiCashPoolPaymaster.sol";
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiCashEntrypoint} from "../src/contracts/interfaces/IShinobiCashEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdrawalVerifier} from "../src/paymaster/interfaces/IWithdrawalVerifier.sol";

/**
 * @title DeploySimpleShinobiCashPoolPaymaster
 * @notice Deployment script for the SimpleShinobiCashPoolPaymaster contract
 * @dev Requires ERC4337 entrypoint, cash pool entrypoint, cash pool, and withdrawal verifier addresses
 */
contract DeploySimpleShinobiCashPoolPaymaster is Script {
    
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get required addresses from environment
        address shinobiCashEntrypoint = vm.envAddress("SHINOBI_ENTRYPOINT_ADDRESS");
        address cashPool = vm.envAddress("CASH_POOL_ADDRESS");
        address withdrawalVerifier = vm.envAddress("WITHDRAWAL_VERIFIER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimpleShinobiCashPoolPaymaster contract
        SimpleShinobiCashPoolPaymaster paymaster = new SimpleShinobiCashPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(cashPool)
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("SimpleShinobiCashPoolPaymaster deployed at:", address(paymaster));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("ERC4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("Shinobi Cash Entrypoint:", shinobiCashEntrypoint);
        console.log("Cash Pool:", cashPool);
        console.log("Withdrawal Verifier:", withdrawalVerifier);
        
        return address(paymaster);
    }
}