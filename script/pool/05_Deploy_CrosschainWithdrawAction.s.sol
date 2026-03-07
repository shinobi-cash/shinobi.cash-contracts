// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {CrosschainWithdrawFacet} from "../../src/pool/facets/CrosschainWithdrawFacet.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../src/verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";

/**
 * @title Deploy_CrosschainWithdrawFacet
 * @notice Deploy CrosschainWithdrawFacet (requires CrosschainWithdrawalVerifier)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (diamondCrosschainWithdrawFacet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/05_Deploy_CrosschainWithdrawFacet.s.sol:Deploy_CrosschainWithdrawFacet \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_CrosschainWithdrawFacet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 5: CrosschainWithdrawFacet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainWithdrawFacet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("CrosschainWithdrawFacet already deployed:", existing);
            return;
        }

        address crosschainVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdrawal");
        require(crosschainVerifier != address(0), "CrosschainWithdrawalVerifier not deployed. Run Step 1 first.");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new CrosschainWithdrawFacet(ICrosschainWithdrawalProofVerifier(crosschainVerifier)));
        vm.stopBroadcast();

        DeploymentWriter.writeContract(poolKey, "diamondCrosschainWithdrawFacet", addr, blockBefore);

        console.log("CrosschainWithdrawFacet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 06_Deploy_Withdraw2Facet.s.sol ...", poolKey);
    }
}
