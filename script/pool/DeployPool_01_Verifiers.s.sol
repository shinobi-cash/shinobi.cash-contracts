// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// ZK Verifiers - Standard withdrawal (1:1)
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";
import {CrossChainWithdrawalVerifier} from "../../src/core/verifiers/CrossChainWithdrawalVerifier.sol";

// ZK Verifiers - Withdraw2 (2:1)
import {Withdraw2Verifier} from "../../src/core/verifiers/Withdraw2Verifier.sol";
import {CrossChainWithdraw2Verifier} from "../../src/core/verifiers/CrossChainWithdraw2Verifier.sol";

/**
 * @title DeployPool_01_Verifiers
 * @notice Deploy ZK verifiers on pool chain (skips already deployed)
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_01_Verifiers.s.sol:DeployPool_01_Verifiers \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployPool_01_Verifiers is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  POOL DEPLOYMENT - Step 1: Verifiers");
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

        // Check if all already deployed
        if (existingWithdrawal != address(0) &&
            existingCommitment != address(0) &&
            existingCrossChain != address(0) &&
            existingWithdraw2 != address(0) &&
            existingCrossChainWithdraw2 != address(0)) {
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

        vm.startBroadcast(deployerPrivateKey);

        // Initialize deployment file if needed
        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        // 1. Deploy WithdrawalVerifier
        if (existingWithdrawal != address(0)) {
            console.log("1. WithdrawalVerifier already deployed:", existingWithdrawal);
        } else {
            console.log("1. Deploying WithdrawalVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new WithdrawalVerifier());
            DeploymentWriter.writeVerifier(poolKey, "withdrawal", addr, blockBefore);
            console.log("   Address:", addr);
            console.log("   Block:", blockBefore);
        }

        // 2. Deploy CommitmentVerifier
        if (existingCommitment != address(0)) {
            console.log("2. CommitmentVerifier already deployed:", existingCommitment);
        } else {
            console.log("2. Deploying CommitmentVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CommitmentVerifier());
            DeploymentWriter.writeVerifier(poolKey, "commitment", addr, blockBefore);
            console.log("   Address:", addr);
            console.log("   Block:", blockBefore);
        }

        // 3. Deploy CrossChainWithdrawalVerifier
        if (existingCrossChain != address(0)) {
            console.log("3. CrossChainWithdrawalVerifier already deployed:", existingCrossChain);
        } else {
            console.log("3. Deploying CrossChainWithdrawalVerifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CrossChainWithdrawalVerifier());
            DeploymentWriter.writeVerifier(poolKey, "crossChainWithdrawal", addr, blockBefore);
            console.log("   Address:", addr);
            console.log("   Block:", blockBefore);
        }

        // 4. Deploy Withdraw2Verifier
        if (existingWithdraw2 != address(0)) {
            console.log("4. Withdraw2Verifier already deployed:", existingWithdraw2);
        } else {
            console.log("4. Deploying Withdraw2Verifier...");
            uint256 blockBefore = block.number;
            address addr = address(new Withdraw2Verifier());
            DeploymentWriter.writeVerifier(poolKey, "withdraw2", addr, blockBefore);
            console.log("   Address:", addr);
            console.log("   Block:", blockBefore);
        }

        // 5. Deploy CrossChainWithdraw2Verifier
        if (existingCrossChainWithdraw2 != address(0)) {
            console.log("5. CrossChainWithdraw2Verifier already deployed:", existingCrossChainWithdraw2);
        } else {
            console.log("5. Deploying CrossChainWithdraw2Verifier...");
            uint256 blockBefore = block.number;
            address addr = address(new CrossChainWithdraw2Verifier());
            DeploymentWriter.writeVerifier(poolKey, "crossChainWithdraw2", addr, blockBefore);
            console.log("   Address:", addr);
            console.log("   Block:", blockBefore);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  VERIFIERS COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployPool_02_Entrypoint.s.sol ...", poolKey);
    }
}
