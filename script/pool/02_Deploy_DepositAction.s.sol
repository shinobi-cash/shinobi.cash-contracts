// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {DepositFacet} from "../../src/pool/facets/DepositFacet.sol";

/**
 * @title Deploy_DepositFacet
 * @notice Deploy DepositFacet (no verifier dependency)
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json (diamondDepositFacet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/02_Deploy_DepositFacet.s.sol:Deploy_DepositFacet --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_DepositFacet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 2: DepositFacet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondDepositFacet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("DepositFacet already deployed:", existing);
            return;
        }

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new DepositFacet());
        DeploymentWriter.writeContract(poolKey, "diamondDepositFacet", addr, blockBefore);
        vm.stopBroadcast();

        console.log("DepositFacet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 03_Deploy_CrosschainDepositFacet.s.sol ...", poolKey);
    }
}
