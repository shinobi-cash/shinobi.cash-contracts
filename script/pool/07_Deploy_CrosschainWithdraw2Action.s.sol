// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {CrosschainWithdraw2Action} from "../../src/pool/facets/CrosschainWithdraw2Action.sol";
import {ICrosschainWithdraw2Verifier} from "../../src/verifiers/interfaces/ICrosschainWithdraw2Verifier.sol";

/**
 * @title Deploy_CrosschainWithdraw2Action
 * @notice Deploy CrosschainWithdraw2Action (requires CrosschainWithdraw2Verifier)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (crosschainWithdraw2)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/07_Deploy_CrosschainWithdraw2Action.s.sol:Deploy_CrosschainWithdraw2Action --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_CrosschainWithdraw2Action is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 7: CrosschainWithdraw2Action");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "crosschainWithdraw2");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("CrosschainWithdraw2Action already deployed:", existing);
            return;
        }

        address crosschainWithdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2");
        require(crosschainWithdraw2Verifier != address(0), "CrosschainWithdraw2Verifier not deployed. Run Step 1 first.");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new CrosschainWithdraw2Action(ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)));
        DeploymentWriter.writeContract(poolKey, "crosschainWithdraw2", addr, blockBefore);
        vm.stopBroadcast();

        console.log("CrosschainWithdraw2Action deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 08_Deploy_RagequitAction.s.sol ...", poolKey);
    }
}
