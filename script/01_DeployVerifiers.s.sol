// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// ZK Verifiers
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";
import {CrossChainWithdrawalVerifier} from "../src/paymaster/contracts/CrossChainWithdrawalVerifier.sol";

/**
 * @title 01_DeployVerifiers
 * @notice Deploy ZK proof verifiers
 */
contract DeployVerifiers is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 1: Deploy ZK Verifiers ===");
        console.log("Deployer:", deployer);
        console.log("");

        // Deploy verifiers
        address withdrawalVerifier = address(new WithdrawalVerifier());
        address commitmentVerifier = address(new CommitmentVerifier());
        address crossChainVerifier = address(new CrossChainWithdrawalVerifier());

        console.log("Withdrawal Verifier:", withdrawalVerifier);
        console.log("Commitment Verifier:", commitmentVerifier);
        console.log("Cross-Chain Verifier:", crossChainVerifier);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save these addresses for next steps ===");
    }
}
