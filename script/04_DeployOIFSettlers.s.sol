// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OIF Settlers
import {ShinobiInputSettler} from "../src/oif/contracts/ShinobiInputSettler.sol";
import {ShinobiDepositOutputSettler} from "../src/oif/contracts/ShinobiDepositOutputSettler.sol";
import {ShinobiWithdrawalOutputSettler} from "../src/oif/contracts/ShinobiWithdrawalOutputSettler.sol";

/**
 * @title 04_DeployOIFSettlers
 * @notice Deploy Shinobi Input and Output Settlers for OIF protocol
 * @dev Deploys separate output settlers for deposits and withdrawals
 *
 * @dev Required env vars:
 *      - SHINOBI_CASH_ENTRYPOINT_PROXY: Entrypoint address for Input Settler
 *      - INTENT_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum for deposit validation
 *      - FILL_ORACLE_ARBITRUM_SEPOLIA: Oracle on Arbitrum for withdrawal fill validation
 *
 * @dev Deployment order:
 *      1. ShinobiInputSettler (with entrypoint)
 *      2. ShinobiDepositOutputSettler (with intentOracle)
 *      3. ShinobiWithdrawalOutputSettler (with fillOracle)
 */
contract DeployOIFSettlers is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get required addresses
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address intentOracle = vm.envAddress("INTENT_ORACLE_ARBITRUM_SEPOLIA");
        address fillOracle = vm.envAddress("FILL_ORACLE_ARBITRUM_SEPOLIA");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 4: Deploy OIF Settlers ===");
        console.log("Deployer:", deployer);
        console.log("Entrypoint:", entrypoint);
        console.log("Intent Oracle:", intentOracle);
        console.log("Fill Oracle:", fillOracle);
        console.log("");

        // 1. Deploy Input Settler (for withdrawals - origin chain)
        console.log("1. Deploying Input Settler...");
        address inputSettler = address(new ShinobiInputSettler(entrypoint));
        console.log("   Shinobi Input Settler:", inputSettler);

        // 2. Deploy Deposit Output Settler (for deposits - destination/pool chain)
        console.log("2. Deploying Deposit Output Settler...");
        address depositOutputSettler = address(new ShinobiDepositOutputSettler(deployer, intentOracle));
        console.log("   Shinobi Deposit Output Settler:", depositOutputSettler);

        // 3. Deploy Withdrawal Output Settler (for withdrawals - destination/user chain)
        console.log("3. Deploying Withdrawal Output Settler...");
        address withdrawalOutputSettler = address(new ShinobiWithdrawalOutputSettler(deployer, fillOracle));
        console.log("   Shinobi Withdrawal Output Settler:", withdrawalOutputSettler);

        vm.stopBroadcast();

        console.log("");
        console.log("=== OIF Settlers Deployment Complete ===");
        console.log("");
        console.log("Save these addresses:");
        console.log("INPUT_SETTLER_ARBITRUM_SEPOLIA=", inputSettler);
        console.log("DEPOSIT_OUTPUT_SETTLER_ARBITRUM_SEPOLIA=", depositOutputSettler);
        console.log("WITHDRAWAL_OUTPUT_SETTLER_BASE_SEPOLIA=", withdrawalOutputSettler);
        console.log("");
        console.log("NOTE: Configure these in the entrypoints:");
        console.log("- ShinobiCashEntrypoint uses: inputSettler, withdrawalOutputSettler");
        console.log("- Deposit entrypoint uses: inputSettler, depositOutputSettler");
    }
}
