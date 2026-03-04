// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Facets
import {AdminFacet} from "../../src/diamond/facets/AdminFacet.sol";
import {ViewFacet} from "../../src/diamond/facets/ViewFacet.sol";
import {DepositFacet} from "../../src/diamond/facets/DepositFacet.sol";
import {WithdrawFacet} from "../../src/diamond/facets/WithdrawFacet.sol";
import {CrosschainWithdrawFacet} from "../../src/diamond/facets/CrosschainWithdrawFacet.sol";
import {Withdraw2Facet} from "../../src/diamond/facets/Withdraw2Facet.sol";
import {CrosschainWithdraw2Facet} from "../../src/diamond/facets/CrosschainWithdraw2Facet.sol";
import {RagequitFacet} from "../../src/diamond/facets/RagequitFacet.sol";
import {RefundFacet} from "../../src/diamond/facets/RefundFacet.sol";

// Verifier interfaces
import {IVerifier} from "interfaces/IVerifier.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../src/core/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";

/**
 * @title DeployDiamond_01_Facets
 * @notice Deploy all 9 diamond facets (reuses existing verifiers)
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json (verifiers)
 * Output: deployments/{POOL_KEY}.json (facet addresses)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/diamond/DeployDiamond_01_Facets.s.sol:DeployDiamond_01_Facets \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployDiamond_01_Facets is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("  DIAMOND DEPLOYMENT - Step 1: Facets");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("");

        // Read verifier addresses (deployed via pool/DeployPool_01_Verifiers)
        address withdrawalVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdrawal");
        address crosschainVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdrawal");
        address withdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2");
        address crosschainWithdraw2Verifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2");
        address commitmentVerifier = DeploymentWriter.readContractAddress(poolKey, "verifiers", "commitment");

        require(withdrawalVerifier != address(0), "WithdrawalVerifier not deployed");
        require(crosschainVerifier != address(0), "CrosschainVerifier not deployed");
        require(withdraw2Verifier != address(0), "Withdraw2Verifier not deployed");
        require(crosschainWithdraw2Verifier != address(0), "CrosschainWithdraw2Verifier not deployed");
        require(commitmentVerifier != address(0), "CommitmentVerifier not deployed");

        if (!DeploymentWriter.deploymentExists(poolKey)) {
            DeploymentWriter.initDeployment(poolKey, poolConfig.chainId, deployer);
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. AdminFacet
        _deploy(poolKey, "diamondAdminFacet", "AdminFacet", address(new AdminFacet()));

        // 2. ViewFacet
        _deploy(poolKey, "diamondViewFacet", "ViewFacet", address(new ViewFacet()));

        // 3. DepositFacet
        _deploy(poolKey, "diamondDepositFacet", "DepositFacet", address(new DepositFacet()));

        // 4. WithdrawFacet
        _deploy(poolKey, "diamondWithdrawFacet", "WithdrawFacet",
            address(new WithdrawFacet(IVerifier(withdrawalVerifier))));

        // 5. CrosschainWithdrawFacet
        _deploy(poolKey, "diamondCrosschainWithdrawFacet", "CrosschainWithdrawFacet",
            address(new CrosschainWithdrawFacet(ICrosschainWithdrawalProofVerifier(crosschainVerifier))));

        // 6. Withdraw2Facet
        _deploy(poolKey, "diamondWithdraw2Facet", "Withdraw2Facet",
            address(new Withdraw2Facet(IWithdraw2Verifier(withdraw2Verifier))));

        // 7. CrosschainWithdraw2Facet
        _deploy(poolKey, "diamondCrosschainWithdraw2Facet", "CrosschainWithdraw2Facet",
            address(new CrosschainWithdraw2Facet(ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier))));

        // 8. RagequitFacet
        _deploy(poolKey, "diamondRagequitFacet", "RagequitFacet",
            address(new RagequitFacet(IVerifier(commitmentVerifier))));

        // 9. RefundFacet
        _deploy(poolKey, "diamondRefundFacet", "RefundFacet", address(new RefundFacet()));

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  FACETS COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script DeployDiamond_02_Diamond.s.sol ...", poolKey);
    }

    function _deploy(string memory poolKey, string memory key, string memory name, address addr) internal {
        address existing = DeploymentWriter.readContractAddress(poolKey, "contracts", key);
        if (existing != address(0)) {
            console.log("%s already deployed: %s", name, existing);
            return;
        }
        DeploymentWriter.writeContract(poolKey, key, addr, block.number);
        console.log("%s deployed: %s", name, addr);
    }
}
