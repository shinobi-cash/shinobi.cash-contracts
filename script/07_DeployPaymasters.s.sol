// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Paymasters
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/CrossChainWithdrawalPaymaster.sol";
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/SimpleShinobiCashPoolPaymaster.sol";

// Interfaces
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title 07_DeployPaymasters
 * @notice Deploy ERC-4337 Paymasters for gas sponsorship
 * @dev Requires: ENTRYPOINT, ETH_POOL env vars
 */
contract DeployPaymasters is Script {
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address ethPool = vm.envAddress("SHINOBI_CASH_ETH_POOL");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 7: Deploy Paymasters ===");
        console.log("Deployer:", deployer);
        console.log("ERC-4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("Shinobi Entrypoint:", entrypoint);
        console.log("");

        // Deploy Cross-Chain Withdrawal Paymaster
        console.log("1. Deploying Cross-Chain Withdrawal Paymaster...");
        address payable crossChainPaymaster = payable(address(new CrossChainWithdrawalPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            IShinobiCashPool(ethPool)
        )));
        console.log("   Cross-Chain Paymaster:", crossChainPaymaster);

        // Deploy Simple Privacy Pool Paymaster
        console.log("2. Deploying Simple Privacy Pool Paymaster...");
        address payable simplePaymaster = payable(address(new SimpleShinobiCashPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            IPrivacyPool(ethPool)
        )));
        console.log("   Simple Paymaster:", simplePaymaster);

        // Fund paymasters for gas sponsorship
        console.log("3. Funding Paymasters...");
        CrossChainWithdrawalPaymaster(crossChainPaymaster).deposit{value: 0.01 ether}();
        SimpleShinobiCashPoolPaymaster(simplePaymaster).deposit{value: 0.01 ether}();
        console.log("   Paymasters funded with 0.01 ETH each");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Paymasters deployed and funded ===");
        console.log("CROSS_CHAIN_PAYMASTER:", crossChainPaymaster);
        console.log("SIMPLE_PAYMASTER:", simplePaymaster);
    }
}
