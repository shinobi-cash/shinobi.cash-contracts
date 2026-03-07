// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";
import {Constants} from "../../src/pool/libraries/Constants.sol";

import {ShinobiPool} from "../../src/pool/ShinobiPool.sol";

/**
 * @title Deploy_ShinobiPool
 * @notice Deploy the ShinobiPool proxy with all actions
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (actions)
 * Output: deployments/{POOL_KEY}.json (shinobiPool)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/09_Deploy_ShinobiPool.s.sol:Deploy_ShinobiPool --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_ShinobiPool is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  Step 9: ShinobiPool");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Check if already deployed
        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "shinobiPool");
        if (existing != address(0) && existing.code.length > 0) {
            console.log("ShinobiPool already deployed:", existing);
            console.log("Skipping.");
            return;
        }

        address[] memory facets = _loadFacets(poolKey);

        // Roles: admin = deployer, aspPostman = deployer (updated later)
        address admin = vm.envOr("DIAMOND_ADMIN", deployer);
        address aspPostman = vm.envOr("ASP_POSTMAN", deployer);

        console.log("Admin:", admin);
        console.log("ASP Postman:", aspPostman);
        console.log("Asset: ETH (native)");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        uint256 blockBefore = block.number;
        ShinobiPool diamond = new ShinobiPool(
            ShinobiPool.InitParams({
                asset: Constants.NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: facets
            })
        );
        DeploymentWriter.writeContract(poolKey, "shinobiPool", address(diamond), blockBefore);
        vm.stopBroadcast();

        console.log("ShinobiPool deployed:", address(diamond));
        console.log("Block:", blockBefore);

        console.log("");
        console.log("Next: POOL_KEY=%s forge script 10_Deploy_Settlers.s.sol ...", poolKey);
    }

    function _loadFacets(string memory poolKey) internal view returns (address[] memory facets) {
        facets = new address[](7);
        facets[0] = DeploymentWriter.readContractAddress(poolKey, "contracts", "deposit");
        facets[1] = DeploymentWriter.readContractAddress(poolKey, "contracts", "crosschainDeposit");
        facets[2] = DeploymentWriter.readContractAddress(poolKey, "contracts", "withdraw");
        facets[3] = DeploymentWriter.readContractAddress(poolKey, "contracts", "crosschainWithdraw");
        facets[4] = DeploymentWriter.readContractAddress(poolKey, "contracts", "withdraw2");
        facets[5] = DeploymentWriter.readContractAddress(poolKey, "contracts", "crosschainWithdraw2");
        facets[6] = DeploymentWriter.readContractAddress(poolKey, "contracts", "ragequit");

        require(facets[0] != address(0), "DepositAction not deployed");
        require(facets[1] != address(0), "CrosschainDepositAction not deployed");
        require(facets[2] != address(0), "WithdrawAction not deployed");
        require(facets[3] != address(0), "CrosschainWithdrawAction not deployed");
        require(facets[4] != address(0), "Withdraw2Action not deployed");
        require(facets[5] != address(0), "CrosschainWithdraw2Action not deployed");
        require(facets[6] != address(0), "RagequitAction not deployed");
    }
}
