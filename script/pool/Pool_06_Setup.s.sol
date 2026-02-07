// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";
import {Constants} from "contracts/lib/Constants.sol";

// Contracts to configure
import {ShinobiCashEntrypoint} from "../../src/core/ShinobiCashEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";

/**
 * @title Pool_06_Setup
 * @notice Configure ShinobiCashEntrypoint with pool and settlers
 * @dev Configuration step - skips already configured items
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Reads:  deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/Pool_06_Setup.s.sol:Pool_06_Setup \
 *     --rpc-url arbitrum-sepolia --broadcast
 */
contract Pool_06_Setup is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        // Read addresses from deployment file
        address entrypoint = DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint");
        address ethPool = DeploymentWriter.readContractAddress(poolKey, "contracts", "ethPool");
        address inputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "inputSettler");
        address depositOutputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "depositOutputSettler");

        require(entrypoint != address(0), "Entrypoint not deployed");
        require(ethPool != address(0), "ETH Pool not deployed");
        require(inputSettler != address(0), "InputSettler not deployed");
        require(depositOutputSettler != address(0), "DepositOutputSettler not deployed");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  POOL SETUP - Step 6");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Using from deployment file:");
        console.log("  Entrypoint:", entrypoint);
        console.log("  ETH Pool:", ethPool);
        console.log("  InputSettler:", inputSettler);
        console.log("  DepositOutputSettler:", depositOutputSettler);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        ShinobiCashEntrypoint entrypointContract = ShinobiCashEntrypoint(payable(entrypoint));

        // 1. Register ETH Privacy Pool
        console.log("1. Registering ETH Privacy Pool...");
        try entrypointContract.registerPool(
            IERC20(Constants.NATIVE_ASSET),
            IPrivacyPool(ethPool),
            poolConfig.minimumDeposit,
            poolConfig.vettingFeeBPS,
            poolConfig.maxRelayFeeBPS
        ) {
            console.log("   Minimum Deposit:", poolConfig.minimumDeposit, "wei");
            console.log("   Vetting Fee:", poolConfig.vettingFeeBPS, "BPS");
            console.log("   Max Relay Fee:", poolConfig.maxRelayFeeBPS, "BPS");
        } catch {
            console.log("   Already registered, skipping.");
        }

        // 2. Set Withdrawal Input Settler
        console.log("2. Setting Withdrawal Input Settler...");
        try entrypointContract.setWithdrawalInputSettler(inputSettler) {
            console.log("   Set to:", inputSettler);
        } catch {
            console.log("   Already set, skipping.");
        }

        // 3. Set Deposit Output Settler
        console.log("3. Setting Deposit Output Settler...");
        try entrypointContract.setDepositOutputSettler(depositOutputSettler) {
            console.log("   Set to:", depositOutputSettler);
        } catch {
            console.log("   Already set, skipping.");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  POOL SETUP COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Pool chain is ready!");
        console.log("");
        console.log("Next: Add origin chains using script/chains/AddChain_* scripts");
    }
}
