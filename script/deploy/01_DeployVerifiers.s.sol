// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// ZK Verifiers - Standard withdrawal (1:1)
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";
import {CrossChainWithdrawalVerifier} from "../src/core/verifiers/CrossChainWithdrawalVerifier.sol";

// ZK Verifiers - Withdraw2 (2:1)
import {Withdraw2Verifier} from "../src/core/verifiers/Withdraw2Verifier.sol";
import {CrossChainWithdraw2Verifier} from "../src/core/verifiers/CrossChainWithdraw2Verifier.sol";

/**
 * @title 01_DeployVerifiers
 * @notice Deploy ZK proof verifiers for all withdrawal types
 */
contract DeployVerifiers is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 1: Deploy ZK Verifiers ===");
        console.log("Deployer:", deployer);
        console.log("");

        // Standard verifiers (1:1 withdrawal)
        address withdrawalVerifier = address(new WithdrawalVerifier());
        address commitmentVerifier = address(new CommitmentVerifier());
        address crossChainVerifier = address(new CrossChainWithdrawalVerifier());

        // Withdraw2 verifiers (2:1 withdrawal)
        address withdraw2Verifier = address(new Withdraw2Verifier());
        address crossChainWithdraw2Verifier = address(new CrossChainWithdraw2Verifier());

        console.log("=== Standard Withdrawal Verifiers (1:1) ===");
        console.log("Withdrawal Verifier:", withdrawalVerifier);
        console.log("Commitment Verifier:", commitmentVerifier);
        console.log("Cross-Chain Verifier:", crossChainVerifier);
        console.log("");
        console.log("=== Withdraw2 Verifiers (2:1) ===");
        console.log("Withdraw2 Verifier (9 signals):", withdraw2Verifier);
        console.log("CrossChainWithdraw2 Verifier (10 signals):", crossChainWithdraw2Verifier);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Save these addresses for next steps ===");
        console.log("WITHDRAWAL_VERIFIER=", withdrawalVerifier);
        console.log("COMMITMENT_VERIFIER=", commitmentVerifier);
        console.log("CROSSCHAIN_WITHDRAWAL_VERIFIER=", crossChainVerifier);
        console.log("WITHDRAW2_VERIFIER=", withdraw2Verifier);
        console.log("CROSSCHAIN_WITHDRAW2_VERIFIER=", crossChainWithdraw2Verifier);
    }
}
