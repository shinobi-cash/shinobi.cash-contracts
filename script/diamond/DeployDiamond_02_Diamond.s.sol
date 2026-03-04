// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";
import {Constants} from "contracts/lib/Constants.sol";

import {PoolDiamond} from "../../src/diamond/PoolDiamond.sol";

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

        // Read all facet addresses
        address adminFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondAdminFacet");
        address viewFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondViewFacet");
        address depositFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondDepositFacet");
        address withdrawFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdrawFacet");
        address crosschainWithdrawFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainWithdrawFacet");
        address withdraw2Facet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondWithdraw2Facet");
        address crosschainWithdraw2Facet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondCrosschainWithdraw2Facet");
        address ragequitFacet = DeploymentWriter.readContractAddress(poolKey, "contracts", "diamondRagequitFacet");

        require(adminFacet != address(0), "AdminFacet not deployed");
        require(viewFacet != address(0), "ViewFacet not deployed");
        require(depositFacet != address(0), "DepositFacet not deployed");
        require(withdrawFacet != address(0), "WithdrawFacet not deployed");
        require(crosschainWithdrawFacet != address(0), "CrosschainWithdrawFacet not deployed");
        require(withdraw2Facet != address(0), "Withdraw2Facet not deployed");
        require(crosschainWithdraw2Facet != address(0), "CrosschainWithdraw2Facet not deployed");
        require(ragequitFacet != address(0), "RagequitFacet not deployed");

        // Roles: admin = deployer, aspPostman = deployer (updated later), diamondAdmin = deployer
        address admin = vm.envOr("DIAMOND_ADMIN", deployer);
        address aspPostman = vm.envOr("ASP_POSTMAN", deployer);
        address diamondAdmin = vm.envOr("DIAMOND_UPGRADE_ADMIN", deployer);

        console.log("Admin:", admin);
        console.log("ASP Postman:", aspPostman);
        console.log("Diamond Admin:", diamondAdmin);
        console.log("Asset: ETH (native)");
        console.log("");

        // Build facets array
        address[] memory facets = new address[](8);
        facets[0] = adminFacet;
        facets[1] = viewFacet;
        facets[2] = depositFacet;
        facets[3] = withdrawFacet;
        facets[4] = crosschainWithdrawFacet;
        facets[5] = withdraw2Facet;
        facets[6] = crosschainWithdraw2Facet;
        facets[7] = ragequitFacet;

        vm.startBroadcast(deployerPrivateKey);

        PoolDiamond.InitParams memory params = PoolDiamond.InitParams({
            asset: Constants.NATIVE_ASSET,
            admin: admin,
            aspPostman: aspPostman,
            diamondAdmin: diamondAdmin,
            facets: facets
        });

        uint256 blockBefore = block.number;
        PoolDiamond diamond = new PoolDiamond(params);
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
}
