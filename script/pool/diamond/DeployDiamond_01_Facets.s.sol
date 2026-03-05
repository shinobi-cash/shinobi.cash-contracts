// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../../config/ChainConfig.sol";
import {DeploymentWriter} from "../../config/DeploymentWriter.sol";

// Facets
import {DepositFacet} from "../../../src/pool/facets/DepositFacet.sol";
import {CrosschainDepositFacet} from "../../../src/pool/facets/CrosschainDepositFacet.sol";
import {WithdrawFacet} from "../../../src/pool/facets/WithdrawFacet.sol";
import {CrosschainWithdrawFacet} from "../../../src/pool/facets/CrosschainWithdrawFacet.sol";
import {Withdraw2Facet} from "../../../src/pool/facets/Withdraw2Facet.sol";
import {CrosschainWithdraw2Facet} from "../../../src/pool/facets/CrosschainWithdraw2Facet.sol";
import {RagequitFacet} from "../../../src/pool/facets/RagequitFacet.sol";

// Verifier interfaces
import {IWithdrawalVerifier} from "../../../src/verifiers/interfaces/IWithdrawalVerifier.sol";
import {IRagequitVerifier} from "../../../src/verifiers/interfaces/IRagequitVerifier.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../../src/verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../../src/verifiers/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../../src/verifiers/interfaces/ICrosschainWithdraw2Verifier.sol";

/**
 * @title DeployDiamond_01_Facets
 * @notice Deploy all 7 operational facets (reuses existing verifiers)
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

        // 1. DepositFacet
        _deploy(poolKey, "diamondDepositFacet", "DepositFacet", address(new DepositFacet()));

        // 2. CrosschainDepositFacet
        _deploy(poolKey, "diamondCrosschainDepositFacet", "CrosschainDepositFacet", address(new CrosschainDepositFacet()));

        // 3. WithdrawFacet
        _deploy(poolKey, "diamondWithdrawFacet", "WithdrawFacet",
            address(new WithdrawFacet(IWithdrawalVerifier(withdrawalVerifier))));

        // 4. CrosschainWithdrawFacet
        _deploy(poolKey, "diamondCrosschainWithdrawFacet", "CrosschainWithdrawFacet",
            address(new CrosschainWithdrawFacet(ICrosschainWithdrawalProofVerifier(crosschainVerifier))));

        // 5. Withdraw2Facet
        _deploy(poolKey, "diamondWithdraw2Facet", "Withdraw2Facet",
            address(new Withdraw2Facet(IWithdraw2Verifier(withdraw2Verifier))));

        // 6. CrosschainWithdraw2Facet
        _deploy(poolKey, "diamondCrosschainWithdraw2Facet", "CrosschainWithdraw2Facet",
            address(new CrosschainWithdraw2Facet(ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier))));

        // 7. RagequitFacet
        _deploy(poolKey, "diamondRagequitFacet", "RagequitFacet",
            address(new RagequitFacet(IRagequitVerifier(commitmentVerifier))));

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
