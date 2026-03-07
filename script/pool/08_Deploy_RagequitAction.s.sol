// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {RagequitFacet} from "../../src/pool/facets/RagequitFacet.sol";
import {IRagequitVerifier} from "../../src/verifiers/interfaces/IRagequitVerifier.sol";

/**
 * @title Deploy_RagequitFacet
 * @notice Deploy RagequitFacet (requires CommitmentVerifier)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (diamondRagequitFacet)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/08_Deploy_RagequitFacet.s.sol:Deploy_RagequitFacet --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_RagequitFacet is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 8: RagequitFacet");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondRagequitFacet");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("RagequitFacet already deployed:", existing);
            return;
        }

        address commitmentVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "commitment");
        require(commitmentVerifier != address(0), "CommitmentVerifier not deployed. Run Step 1 first.");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        address addr = address(new RagequitFacet(IRagequitVerifier(commitmentVerifier)));
        DeploymentWriter.writeContract(poolKey, "diamondRagequitFacet", addr, blockBefore);
        vm.stopBroadcast();

        console.log("RagequitFacet deployed:", addr);
        console.log("");
        console.log("Next: POOL_KEY=%s forge script 09_Deploy_PoolDiamond.s.sol ...", poolKey);
    }
}
