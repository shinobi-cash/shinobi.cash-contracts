// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Privacy Pool
import {ShinobiCashPoolSimple} from "../../src/core/implementations/ShinobiCashPoolSimple.sol";
import {ICrossChainWithdrawalProofVerifier} from "../../src/core/interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrossChainWithdraw2Verifier} from "../../src/core/interfaces/ICrossChainWithdraw2Verifier.sol";

/**
 * @title DeployPool_03_PrivacyPool
 * @notice Deploy ShinobiCashPoolSimple (ETH privacy pool) - skips if deployed
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_03_PrivacyPool.s.sol:DeployPool_03_PrivacyPool \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployPool_03_PrivacyPool is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  POOL DEPLOYMENT - Step 3: Privacy Pool");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Check if already deployed
        address existingPool = DeploymentWriter.readContractAddress(poolKey, "contracts", "ethPool");

        if (existingPool != address(0)) {
            console.log("ETH Pool already deployed:", existingPool);
            console.log("");
            console.log("Skipping deployment.");
            return;
        }

        // Read addresses from previous deployments
        address entrypoint = DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint");
        address withdrawalVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdrawal");
        address commitmentVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "commitment");
        address crossChainWithdrawalVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdrawal");
        address withdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2");
        address crossChainWithdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2");

        require(entrypoint != address(0), "Entrypoint not deployed. Run Step 2 first.");
        require(withdrawalVerifier != address(0), "Verifiers not deployed. Run Step 1 first.");

        console.log("Using from deployment file:");
        console.log("  Entrypoint:", entrypoint);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying ShinobiCashPoolSimple...");
        uint256 blockBefore = block.number;
        ShinobiCashPoolSimple pool = new ShinobiCashPoolSimple(
            entrypoint,
            withdrawalVerifier,
            commitmentVerifier,
            ICrossChainWithdrawalProofVerifier(crossChainWithdrawalVerifier),
            IWithdraw2Verifier(withdraw2Verifier),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );
        DeploymentWriter.writeContract(poolKey, "ethPool", address(pool), blockBefore);
        console.log("   Address:", address(pool));
        console.log("   Block:", blockBefore);
        console.log("   SCOPE:", pool.SCOPE());

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  PRIVACY POOL DEPLOYED");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployPool_04_Settlers.s.sol ...", poolKey);
    }
}
