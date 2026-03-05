// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {Withdraw2Facet} from "../../src/pool/facets/Withdraw2Facet.sol";
import {IWithdraw2Verifier} from "../../src/verifiers/interfaces/IWithdraw2Verifier.sol";

/**
 * @title Deploy_Withdraw2Facet
 * @notice Deploy Withdraw2Facet (requires Withdraw2Verifier)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (diamondWithdraw2Facet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/06_Deploy_Withdraw2Facet.s.sol:Deploy_Withdraw2Facet --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_Withdraw2Facet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 6: Withdraw2Facet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdraw2Facet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("Withdraw2Facet already deployed:", existing);
            return;
        }

        address withdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2");
        require(withdraw2Verifier != address(0), "Withdraw2Verifier not deployed. Run Step 1 first.");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new Withdraw2Facet(IWithdraw2Verifier(withdraw2Verifier)));
        DeploymentWriter.writeContract(poolKey, "diamondWithdraw2Facet", addr, blockBefore);
        vm.stopBroadcast();

        console.log("Withdraw2Facet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 07_Deploy_CrosschainWithdraw2Facet.s.sol ...", poolKey);
    }
}
