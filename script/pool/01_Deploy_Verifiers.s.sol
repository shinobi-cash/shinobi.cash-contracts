// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// ZK Verifiers - Standard withdrawal (1:1)
import {WithdrawalVerifier} from "../../src/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "../../src/verifiers/CommitmentVerifier.sol";
import {CrosschainWithdrawalVerifier} from "../../src/verifiers/CrosschainWithdrawalVerifier.sol";

// ZK Verifiers - Withdraw2 (2:1)
import {Withdraw2Verifier} from "../../src/verifiers/Withdraw2Verifier.sol";
import {CrosschainWithdraw2Verifier} from "../../src/verifiers/CrosschainWithdraw2Verifier.sol";

/**
 * @title Deploy_Verifiers
 * @notice Deploy ZK verifiers on pool chain (skips already deployed)
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/01_Deploy_Verifiers.s.sol:Deploy_Verifiers --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_Verifiers is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 1: Verifiers");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Chain ID:", poolConfig.chainId);
        console.log("Deployer:", deployer);
        console.log("");

        // Check existing deployments
        address existingWithdrawal = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdrawal");
        address existingCommitment = DeploymentWriter.readContractAddress(poolKey, "verifiers", "commitment");
        address existingCrossChain = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdrawal");
        address existingWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2");
        address existingCrossChainWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2");

        // Check if all already deployed (verify on-chain code to avoid simulation-pass false positives)
        if (existingWithdrawal != address(0) && existingWithdrawal.code.length > 0 &&
            existingCommitment != address(0) && existingCommitment.code.length > 0 &&
            existingCrossChain != address(0) && existingCrossChain.code.length > 0 &&
            existingWithdraw2 != address(0) && existingWithdraw2.code.length > 0 &&
            existingCrossChainWithdraw2 != address(0) && existingCrossChainWithdraw2.code.length > 0) {
            console.log("All verifiers already deployed:");
            console.log("  withdrawal:", existingWithdrawal);
            console.log("  commitment:", existingCommitment);
            console.log("  crossChainWithdrawal:", existingCrossChain);
            console.log("  withdraw2:", existingWithdraw2);
            console.log("  crossChainWithdraw2:", existingCrossChainWithdraw2);
            console.log("");
            console.log("Skipping deployment. Delete deployment file to redeploy.");
            return;
        }

        // Initialize deployment file if needed
        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy WithdrawalVerifier
        if (existingWithdrawal != address(0) && existingWithdrawal.code.length > 0) {
            console.log("1. WithdrawalVerifier already deployed:", existingWithdrawal);
        } else {
            console.log("1. Deploying WithdrawalVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new WithdrawalVerifier());
            DeploymentWriter.writeVerifier(poolKey, "withdrawal", addr, blockBefore);
            console.log("   Address:", addr);
        }

        // 2. Deploy CommitmentVerifier
        if (existingCommitment != address(0) && existingCommitment.code.length > 0) {
            console.log("2. CommitmentVerifier already deployed:", existingCommitment);
        } else {
            console.log("2. Deploying CommitmentVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CommitmentVerifier());
            DeploymentWriter.writeVerifier(poolKey, "commitment", addr, blockBefore);
            console.log("   Address:", addr);
        }

        // 3. Deploy CrosschainWithdrawalVerifier
        if (existingCrossChain != address(0) && existingCrossChain.code.length > 0) {
            console.log("3. CrosschainWithdrawalVerifier already deployed:", existingCrossChain);
        } else {
            console.log("3. Deploying CrosschainWithdrawalVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CrosschainWithdrawalVerifier());
            DeploymentWriter.writeVerifier(poolKey, "crossChainWithdrawal", addr, blockBefore);
            console.log("   Address:", addr);
        }

        // 4. Deploy Withdraw2Verifier
        if (existingWithdraw2 != address(0) && existingWithdraw2.code.length > 0) {
            console.log("4. Withdraw2Verifier already deployed:", existingWithdraw2);
        } else {
            console.log("4. Deploying Withdraw2Verifier...");
            uint256 blockBefore = block.number;
            address addr = address(new Withdraw2Verifier());
            DeploymentWriter.writeVerifier(poolKey, "withdraw2", addr, blockBefore);
            console.log("   Address:", addr);
        }

        // 5. Deploy CrosschainWithdraw2Verifier
        if (existingCrossChainWithdraw2 != address(0) && existingCrossChainWithdraw2.code.length > 0) {
            console.log("5. CrosschainWithdraw2Verifier already deployed:", existingCrossChainWithdraw2);
        } else {
            console.log("5. Deploying CrosschainWithdraw2Verifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CrosschainWithdraw2Verifier());
            DeploymentWriter.writeVerifier(poolKey, "crossChainWithdraw2", addr, blockBefore);
            console.log("   Address:", addr);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  VERIFIERS COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 02_Deploy_Deposit.s.sol ...", poolKey);
    }
}
