// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {WithdrawFacet} from "../../src/pool/facets/WithdrawFacet.sol";
import {IWithdrawalVerifier} from "../../src/verifiers/interfaces/IWithdrawalVerifier.sol";

/**
 * @title Deploy_WithdrawFacet
 * @notice Deploy WithdrawFacet (requires WithdrawalVerifier)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (diamondWithdrawFacet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/04_Deploy_WithdrawFacet.s.sol:Deploy_WithdrawFacet --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_WithdrawFacet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 4: WithdrawFacet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdrawFacet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("WithdrawFacet already deployed:", existing);
            return;
        }

        address withdrawalVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdrawal");
        require(withdrawalVerifier != address(0), "WithdrawalVerifier not deployed. Run Step 1 first.");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new WithdrawFacet(IWithdrawalVerifier(withdrawalVerifier)));
        DeploymentWriter.writeContract(poolKey, "diamondWithdrawFacet", addr, blockBefore);
        vm.stopBroadcast();

        console.log("WithdrawFacet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 05_Deploy_CrosschainWithdrawFacet.s.sol ...", poolKey);
    }
}
