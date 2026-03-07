// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {CrosschainDepositFacet} from "../../src/pool/facets/CrosschainDepositFacet.sol";

/**
 * @title Deploy_CrosschainDepositFacet
 * @notice Deploy CrosschainDepositFacet (no verifier dependency)
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json (diamondCrosschainDepositFacet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/03_Deploy_CrosschainDepositFacet.s.sol:Deploy_CrosschainDepositFacet --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_CrosschainDepositFacet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 3: CrosschainDepositFacet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainDepositFacet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("CrosschainDepositFacet already deployed:", existing);
            return;
        }

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new CrosschainDepositFacet());
        DeploymentWriter.writeContract(poolKey, "diamondCrosschainDepositFacet", addr, blockBefore);
        vm.stopBroadcast();

        console.log("CrosschainDepositFacet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 04_Deploy_WithdrawFacet.s.sol ...", poolKey);
    }
}
