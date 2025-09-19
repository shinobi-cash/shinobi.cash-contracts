// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/contracts/CrossChainWithdrawalPaymaster.sol";
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiCashCrossChainHandler} from "../src/contracts/interfaces/IShinobiCashCrossChainHandler.sol";
import {ICrossChainWithdrawalVerifier} from "../src/paymaster/interfaces/ICrossChainWithdrawalVerifier.sol";
import {IShinobiCashEntrypoint} from "../src/contracts/interfaces/IShinobiCashEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title DeployCrossChainWithdrawalPaymaster
 * @notice Deployment script for the CrossChainWithdrawalPaymaster contract
 * @dev Requires ERC4337 entrypoint, Shinobi entrypoint, and cross-chain verifier addresses
 */
contract DeployCrossChainWithdrawalPaymaster is Script {
    
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get required addresses from environment
        address shinobiEntrypoint = vm.envAddress("SHINOBI_ENTRYPOINT_ADDRESS");
        address crossChainVerifier = vm.envAddress("CROSS_CHAIN_VERIFIER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CrossChainWithdrawalPaymaster contract
        CrossChainWithdrawalPaymaster paymaster = new CrossChainWithdrawalPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashCrossChainHandler(shinobiEntrypoint),
            IShinobiCashEntrypoint(shinobiEntrypoint),
            IPrivacyPool(vm.envAddress("PRIVACY_POOL_ADDRESS"))
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("CrossChainWithdrawalPaymaster deployed at:", address(paymaster));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("ERC4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("Shinobi Cash Entrypoint:", shinobiEntrypoint);
        console.log("Cross-Chain Verifier:", crossChainVerifier);
        
        return address(paymaster);
    }
}