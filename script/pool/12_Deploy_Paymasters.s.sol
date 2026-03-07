// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Paymasters
import {WithdrawalPaymaster} from "../../src/paymaster/WithdrawalPaymaster.sol";
import {CrosschainWithdrawalPaymaster} from "../../src/paymaster/CrosschainWithdrawalPaymaster.sol";
import {Withdraw2Paymaster} from "../../src/paymaster/Withdraw2Paymaster.sol";
import {CrosschainWithdraw2Paymaster} from "../../src/paymaster/CrosschainWithdraw2Paymaster.sol";

// Interfaces
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiPool} from "../../src/pool/interfaces/IShinobiPool.sol";
import {IWithdrawalVerifier} from "../../src/verifiers/interfaces/IWithdrawalVerifier.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../src/verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../src/verifiers/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../src/verifiers/interfaces/ICrosschainWithdraw2Verifier.sol";
import {IShinobiInputSettler} from "../../src/oif/interfaces/IShinobiInputSettler.sol";

/**
 * @title Deploy_Paymasters
 * @notice Deploy 4 paymasters for gas sponsorship
 *
 * Input:  config/pools/{POOL_KEY}.json, deployments/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json (paymaster addresses)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/12_Deploy_Paymasters.s.sol:Deploy_Paymasters --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_Paymasters is Script {
    struct Addresses {
        address shinobiPool;
        address erc4337Entrypoint;
        address withdrawalVerifier;
        address crosschainVerifier;
        address withdraw2Verifier;
        address crosschainWithdraw2Verifier;
        address inputSettler;
        address expectedSmartAccount;
    }

    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("==========================================================");
        console.log("  Step 12: Paymasters");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");

        // Check if all already deployed
        address existingSimple = DeploymentWriter.readContractAddress(poolKey, "paymasters", "withdrawal");
        address existingCrosschain = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crosschainWithdrawal");
        address existingWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "withdraw2");
        address existingCrosschainWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crosschainWithdraw2");

        if (existingSimple != address(0) && existingSimple.code.length > 0 &&
            existingCrosschain != address(0) && existingCrosschain.code.length > 0 &&
            existingWithdraw2 != address(0) && existingWithdraw2.code.length > 0 &&
            existingCrosschainWithdraw2 != address(0) && existingCrosschainWithdraw2.code.length > 0) {
            console.log("All paymasters already deployed. Skipping.");
            return;
        }

        Addresses memory addrs = Addresses({
            shinobiPool: DeploymentWriter.readContractAddress(poolKey, "contracts", "shinobiPool"),
            erc4337Entrypoint: poolConfig.erc4337Entrypoint,
            withdrawalVerifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdrawal"),
            crosschainVerifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdrawal"),
            withdraw2Verifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2"),
            crosschainWithdraw2Verifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2"),
            inputSettler: DeploymentWriter.readContractAddress(poolKey, "contracts", "inputSettler"),
            expectedSmartAccount: vm.envOr("EXPECTED_SMART_ACCOUNT", address(0xa3aBDC7f6334CD3EE466A115f30522377787c024))
        });

        require(addrs.shinobiPool != address(0), "ShinobiPool not deployed");
        require(addrs.inputSettler != address(0), "InputSettler not deployed");
        require(addrs.withdrawalVerifier != address(0), "Verifiers not deployed");

        console.log("ERC-4337 EntryPoint:", addrs.erc4337Entrypoint);
        console.log("ShinobiPool:", addrs.shinobiPool);
        console.log("Expected Smart Account:", addrs.expectedSmartAccount);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        _deployWithdrawalPaymaster(poolKey, addrs, existingSimple);
        _deployCrosschainPaymaster(poolKey, addrs, existingCrosschain);
        _deployWithdraw2Paymaster(poolKey, addrs, existingWithdraw2);
        _deployCrosschainWithdraw2Paymaster(poolKey, addrs, existingCrosschainWithdraw2);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  PAYMASTERS COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next (cross-chain):");
        console.log("  1. ORIGIN_KEY=<origin> forge script chains/AddChain_01_DeployOriginContracts.s.sol  (deploy origin)");
        console.log("  2. POOL_KEY=%s ORIGIN_KEY=<origin> forge script chains/AddChain_02_ConfigurePoolChain.s.sol  (configure deposit settler)", poolKey);
        console.log("  3. ORIGIN_KEY=<origin> forge script chains/AddChain_03_ConfigureOriginChain.s.sol  (configure origin)");
        console.log("  4. POOL_KEY=%s ORIGIN_KEY=<origin> forge script pool/13_Setup_WithdrawalChains.s.sol  (withdrawal config)", poolKey);
        console.log("");
        console.log("Next (timelock): POOL_KEY=%s forge script pool/14_Deploy_Timelock.s.sol", poolKey);
    }

    function _deployWithdrawalPaymaster(
        string memory poolKey,
        Addresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0) && existing.code.length > 0) {
            console.log("1. WithdrawalPaymaster already deployed:", existing);
            return;
        }
        console.log("1. Deploying WithdrawalPaymaster...");
        uint256 blockBefore = block.number;
        WithdrawalPaymaster pm = new WithdrawalPaymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiPool(addrs.shinobiPool),
            IWithdrawalVerifier(addrs.withdrawalVerifier)
        );
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        DeploymentWriter.writePaymaster(poolKey, "withdrawal", address(pm), blockBefore);
        console.log("   Address:", address(pm));
    }

    function _deployCrosschainPaymaster(
        string memory poolKey,
        Addresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0) && existing.code.length > 0) {
            console.log("2. CrosschainWithdrawalPaymaster already deployed:", existing);
            return;
        }
        console.log("2. Deploying CrosschainWithdrawalPaymaster...");
        uint256 blockBefore = block.number;
        CrosschainWithdrawalPaymaster pm = new CrosschainWithdrawalPaymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiPool(addrs.shinobiPool),
            ICrosschainWithdrawalProofVerifier(addrs.crosschainVerifier),
            IShinobiInputSettler(addrs.inputSettler)
        );
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        DeploymentWriter.writePaymaster(poolKey, "crosschainWithdrawal", address(pm), blockBefore);
        console.log("   Address:", address(pm));
    }

    function _deployWithdraw2Paymaster(
        string memory poolKey,
        Addresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0) && existing.code.length > 0) {
            console.log("3. Withdraw2Paymaster already deployed:", existing);
            return;
        }
        console.log("3. Deploying Withdraw2Paymaster...");
        uint256 blockBefore = block.number;
        Withdraw2Paymaster pm = new Withdraw2Paymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiPool(addrs.shinobiPool),
            IWithdraw2Verifier(addrs.withdraw2Verifier)
        );
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        DeploymentWriter.writePaymaster(poolKey, "withdraw2", address(pm), blockBefore);
        console.log("   Address:", address(pm));
    }

    function _deployCrosschainWithdraw2Paymaster(
        string memory poolKey,
        Addresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0) && existing.code.length > 0) {
            console.log("4. CrosschainWithdraw2Paymaster already deployed:", existing);
            return;
        }
        console.log("4. Deploying CrosschainWithdraw2Paymaster...");
        uint256 blockBefore = block.number;
        CrosschainWithdraw2Paymaster pm = new CrosschainWithdraw2Paymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiPool(addrs.shinobiPool),
            ICrosschainWithdraw2Verifier(addrs.crosschainWithdraw2Verifier),
            IShinobiInputSettler(addrs.inputSettler)
        );
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        DeploymentWriter.writePaymaster(poolKey, "crosschainWithdraw2", address(pm), blockBefore);
        console.log("   Address:", address(pm));
    }
}
