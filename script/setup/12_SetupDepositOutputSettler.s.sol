// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ShinobiDepositOutputSettler} from "../../src/oif/ShinobiDepositOutputSettler.sol";

/**
 * @title 12_SetupDepositOutputSettler
 * @notice Configure DepositOutputSettler on Arbitrum Sepolia with origin chain configs
 * @dev Run this script on Arbitrum Sepolia (destination chain) after deploying DepositOutputSettler
 *
 * Required env vars:
 *      - DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA: DepositOutputSettler address on Arbitrum
 *      - HYPERLANE_ORACLE_BASE_SEPOLIA: HyperlaneOracle address on Base Sepolia
 *      - SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA: DepositEntrypoint address on Base Sepolia
 *
 * Usage:
 *      forge script script/12_SetupDepositOutputSettler.s.sol:SetupDepositOutputSettler \
 *        --rpc-url arbitrum-sepolia \
 *        --broadcast
 */
contract SetupDepositOutputSettler is Script {
    // Base Sepolia chain ID
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses
        address depositOutputSettlerAddr = vm.envAddress("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA");
        address hyperlaneOracleBaseSepolia = vm.envAddress("HYPERLANE_ORACLE_BASE_SEPOLIA");
        address depositEntrypointBaseSepolia = vm.envAddress("SHINOBI_CASH_DEPOSIT_ENTRYPOINT_BASE_SEPOLIA");

        console.log("=== Step 12: Setup DepositOutputSettler ===");
        console.log("Deployer:", deployer);
        console.log("DepositOutputSettler:", depositOutputSettlerAddr);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        ShinobiDepositOutputSettler settler = ShinobiDepositOutputSettler(payable(depositOutputSettlerAddr));

        // Configure Base Sepolia as an origin chain
        console.log("Configuring Base Sepolia as origin chain...");
        settler.setOriginChainConfig(
            BASE_SEPOLIA_CHAIN_ID,
            hyperlaneOracleBaseSepolia,
            depositEntrypointBaseSepolia
        );
        console.log("  Chain ID:", BASE_SEPOLIA_CHAIN_ID);
        console.log("  HyperlaneOracle:", hyperlaneOracleBaseSepolia);
        console.log("  DepositEntrypoint:", depositEntrypointBaseSepolia);

        vm.stopBroadcast();

        console.log("");
        console.log("=== DepositOutputSettler configuration complete ===");
        console.log("Can now accept deposits from Base Sepolia");
    }
}
