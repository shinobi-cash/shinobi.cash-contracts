// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../../config/ChainConfig.sol";
import {DeploymentWriter} from "../../config/DeploymentWriter.sol";
import {Constants} from "../../../src/pool/libraries/Constants.sol";

import {PoolDiamond} from "../../../src/pool/PoolDiamond.sol";

/**
 * @title DeployDiamond_02_Diamond
 * @notice Deploy the PoolDiamond proxy with all facets
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (facets)
 * Output: deployments/{POOL_KEY}.json (diamond address)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/diamond/DeployDiamond_02_Diamond.s.sol:DeployDiamond_02_Diamond \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployDiamond_02_Diamond is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  DIAMOND DEPLOYMENT - Step 2: PoolDiamond");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Check if already deployed
        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", "poolDiamond");
        if (existing != address(0)) {
            console.log("PoolDiamond already deployed:", existing);
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
        PoolDiamond diamond = new PoolDiamond(
            PoolDiamond.InitParams({
                asset: Constants.NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: facets
            })
        );
        DeploymentWriter.writeContract(poolKey, "poolDiamond", address(diamond), blockBefore);

        console.log("PoolDiamond deployed:", address(diamond));
        console.log("Block:", blockBefore);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  DIAMOND DEPLOYED");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployDiamond_03_Setup.s.sol ...", poolKey);
    }

    function _loadFacets(string memory poolKey) internal view returns (address[] memory facets) {
        facets = new address[](7);
        facets[0] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondDepositFacet");
        facets[1] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainDepositFacet");
        facets[2] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdrawFacet");
        facets[3] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainWithdrawFacet");
        facets[4] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdraw2Facet");
        facets[5] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainWithdraw2Facet");
        facets[6] = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondRagequitFacet");

        require(facets[0] != address(0), "DepositFacet not deployed");
        require(facets[1] != address(0), "CrosschainDepositFacet not deployed");
        require(facets[2] != address(0), "WithdrawFacet not deployed");
        require(facets[3] != address(0), "CrosschainWithdrawFacet not deployed");
        require(facets[4] != address(0), "Withdraw2Facet not deployed");
        require(facets[5] != address(0), "CrosschainWithdraw2Facet not deployed");
        require(facets[6] != address(0), "RagequitFacet not deployed");
    }
}
