// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ShinobiCashPoolSimple} from "../src/contracts/implementations/ShinobiCashPoolSimple.sol";
import {ShinobiCashEntrypoint} from "../src/contracts/ShinobiCashEntrypoint.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "../src/contracts/interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title DeployPoolAndConfigure
 * @notice Deploy new ShinobiCashPoolSimple and configure entrypoint
 */
contract DeployPoolAndConfigure is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get addresses from environment
        address entrypointProxy = vm.envAddress("ENTRYPOINT_PROXY_ADDRESS");
        address withdrawalVerifier = vm.envAddress("WITHDRAWAL_VERIFIER_ADDRESS");
        address commitmentVerifier = vm.envAddress("COMMITMENT_VERIFIER_ADDRESS");
        address crossChainVerifier = vm.envAddress("CROSS_CHAIN_VERIFIER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying Pool & Configuring Entrypoint ===");
        console.log("Entrypoint:", entrypointProxy);
        console.log("Withdrawal Verifier:", withdrawalVerifier);
        console.log("Commitment Verifier:", commitmentVerifier);
        console.log("Cross-Chain Verifier:", crossChainVerifier);

        // 1. Deploy new ShinobiCashPoolSimple
        ShinobiCashPoolSimple newPool = new ShinobiCashPoolSimple(
            entrypointProxy,
            withdrawalVerifier,
            commitmentVerifier,
            ICrossChainWithdrawalProofVerifier(crossChainVerifier)
        );
        
        console.log("New Pool Address:", address(newPool));

        // 2. Register new pool with entrypoint
        ShinobiCashEntrypoint entrypoint = ShinobiCashEntrypoint(payable(entrypointProxy));
        entrypoint.registerPool(
            IERC20(Constants.NATIVE_ASSET), // ETH (address(0))
            IPrivacyPool(address(newPool)),
            0.0001 ether, // MIN_DEPOSIT (0.0001 ETH)
            10,          // VETTING_FEE_BPS (0.1%)
            1500         // MAX_RELAY_FEE_BPS (15%)
        );
        console.log("Pool registered with entrypoint");

        // 3. Set supported chains for cross-chain withdrawals
        entrypoint.updateChainSupport(84532, true); // Base Sepolia
        console.log("Base Sepolia (84532) support enabled");

        // 4. Set Shinobi Input Settler (if provided)
        address inputSettler = vm.envOr("INPUT_SETTLER_ADDRESS", address(0));
        if (inputSettler != address(0)) {
            entrypoint.setInputSettler(inputSettler);
            console.log("Shinobi Input Settler set:", inputSettler);
        } else {
            console.log("No Shinobi Input Settler provided - skipping");
        }

        // 5. Set Shinobi Output Settler (if provided)
        address outputSettler = vm.envOr("OUTPUT_SETTLER_ADDRESS", address(0));
        if (outputSettler != address(0)) {
            entrypoint.setOutputSettler(outputSettler);
            console.log("Shinobi Output Settler set:", outputSettler);
        } else {
            console.log("No Shinobi Output Settler provided - skipping");
        }

        vm.stopBroadcast();

        console.log("Deployment and configuration complete!");
        console.log("NEW_POOL_ADDRESS:", address(newPool));
        console.log("ENTRYPOINT_ADDRESS:", entrypointProxy);
    }
}