// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Shinobi Cash contracts
import {ShinobiCashPoolSimple} from "../src/core/implementations/ShinobiCashPoolSimple.sol";
import {ICrossChainWithdrawalProofVerifier} from "../src/core/interfaces/ICrossChainWithdrawalProofVerifier.sol";

/**
 * @title 03_DeployPrivacyPool
 * @notice Deploy Shinobi ETH Privacy Pool
 * @dev Requires: ENTRYPOINT, WITHDRAWAL_VERIFIER, COMMITMENT_VERIFIER, CROSS_CHAIN_VERIFIER env vars
 */
contract DeployPrivacyPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address withdrawalVerifier = vm.envAddress("WITHDRAWAL_VERIFIER");
        address commitmentVerifier = vm.envAddress("COMMITMENT_VERIFIER");
        address crossChainVerifier = vm.envAddress("CROSSCHAIN_WITHDRAWAL_VERIFIER");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 3: Deploy Shinobi ETH Privacy Pool ===");
        console.log("Deployer:", deployer);
        console.log("Entrypoint:", entrypoint);
        console.log("");

        address ethPool = address(new ShinobiCashPoolSimple(
            entrypoint,
            withdrawalVerifier,
            commitmentVerifier,
            ICrossChainWithdrawalProofVerifier(crossChainVerifier)
        ));

        console.log("Shinobi ETH Privacy Pool:", ethPool);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save this address for next steps ===");
    }
}
