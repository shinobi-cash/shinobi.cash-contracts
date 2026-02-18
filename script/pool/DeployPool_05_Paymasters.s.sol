// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Paymasters
import {ShinobiNativeWithdrawalPaymaster} from "../../src/paymaster/ShinobiNativeWithdrawalPaymaster.sol";
import {ShinobiNativeCrosschainWithdrawalPaymaster} from "../../src/paymaster/ShinobiNativeCrosschainWithdrawalPaymaster.sol";
import {ShinobiNativeWithdraw2Paymaster} from "../../src/paymaster/ShinobiNativeWithdraw2Paymaster.sol";
import {ShinobiNativeCrosschainWithdraw2Paymaster} from "../../src/paymaster/ShinobiNativeCrosschainWithdraw2Paymaster.sol";

// Interfaces
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiCashEntrypoint} from "../../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../../src/core/interfaces/IShinobiCashPool.sol";
import {ShinobiCashPool} from "../../src/core/ShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {IShinobiInputSettler} from "../../src/oif/interfaces/IShinobiInputSettler.sol";

/**
 * @title DeployPool_05_Paymasters
 * @notice Deploy ERC-4337 Paymasters for gas sponsorship - skips if deployed
 *
 * Input:  config/pools/{POOL_KEY}.json
 * Output: deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_05_Paymasters.s.sol:DeployPool_05_Paymasters --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract DeployPool_05_Paymasters is Script {
    struct DeploymentAddresses {
        address entrypoint;
        address ethPool;
        address withdraw2Verifier;
        address crossChainWithdraw2Verifier;
        address inputSettler;
        address expectedSmartAccount;
        address erc4337Entrypoint;
    }

    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("==========================================================");
        console.log("  POOL DEPLOYMENT - Step 5: Paymasters");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");

        // Check existing deployments
        address existingSimple = DeploymentWriter.readContractAddress(poolKey, "paymasters", "simple");
        address existingCrossChain = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crossChain");
        address existingWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "withdraw2");
        address existingCrossChainWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crossChainWithdraw2");

        // Check if all already deployed
        if (existingSimple != address(0) &&
            existingCrossChain != address(0) &&
            existingWithdraw2 != address(0) &&
            existingCrossChainWithdraw2 != address(0)) {
            console.log("All paymasters already deployed:");
            console.log("  simple:", existingSimple);
            console.log("  crossChain:", existingCrossChain);
            console.log("  withdraw2:", existingWithdraw2);
            console.log("  crossChainWithdraw2:", existingCrossChainWithdraw2);
            console.log("");
            console.log("Skipping deployment.");
            return;
        }

        // Build addresses struct
        DeploymentAddresses memory addrs = DeploymentAddresses({
            entrypoint: DeploymentWriter.readContractAddress(poolKey, "contracts", "entrypoint"),
            ethPool: DeploymentWriter.readContractAddress(poolKey, "contracts", "ethPool"),
            withdraw2Verifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "withdraw2"),
            crossChainWithdraw2Verifier: DeploymentWriter.readContractAddress(poolKey, "verifiers", "crossChainWithdraw2"),
            inputSettler: DeploymentWriter.readContractAddress(poolKey, "contracts", "inputSettler"),
            expectedSmartAccount: vm.envOr("EXPECTED_SMART_ACCOUNT", address(0xa3aBDC7f6334CD3EE466A115f30522377787c024)),
            erc4337Entrypoint: poolConfig.erc4337Entrypoint
        });

        require(addrs.entrypoint != address(0), "Entrypoint not deployed");
        require(addrs.inputSettler != address(0), "InputSettler not deployed");
        require(addrs.ethPool != address(0), "ETH Pool not deployed");
        require(addrs.withdraw2Verifier != address(0), "Verifiers not deployed");

        console.log("ERC-4337 EntryPoint:", addrs.erc4337Entrypoint);
        console.log("Expected Smart Account:", addrs.expectedSmartAccount);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy each paymaster
        _deploySimplePaymaster(poolKey, addrs, existingSimple);
        _deployCrosschainPaymaster(poolKey, addrs, existingCrossChain);
        _deployWithdraw2Paymaster(poolKey, addrs, existingWithdraw2);
        _deployCrosschainWithdraw2Paymaster(poolKey, addrs, existingCrossChainWithdraw2);

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  PAYMASTERS COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: POOL_KEY=%s forge script Pool_06_Setup.s.sol ...", poolKey);
    }

    function _deploySimplePaymaster(
        string memory poolKey,
        DeploymentAddresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0)) {
            console.log("1. SimplePaymaster already deployed:", existing);
            return;
        }
        console.log("1. Deploying ShinobiNativeWithdrawalPaymaster...");
        uint256 blockBefore = block.number;
        ShinobiNativeWithdrawalPaymaster pm = new ShinobiNativeWithdrawalPaymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiCashEntrypoint(addrs.entrypoint),
            IPrivacyPool(addrs.ethPool)
        );
        DeploymentWriter.writePaymaster(poolKey, "simple", address(pm), blockBefore);
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        console.log("   Address:", address(pm));
        console.log("   Block:", blockBefore);
    }

    function _deployCrosschainPaymaster(
        string memory poolKey,
        DeploymentAddresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0)) {
            console.log("2. CrossChainPaymaster already deployed:", existing);
            return;
        }
        console.log("2. Deploying ShinobiNativeCrosschainWithdrawalPaymaster...");
        uint256 blockBefore = block.number;
        ShinobiNativeCrosschainWithdrawalPaymaster pm = new ShinobiNativeCrosschainWithdrawalPaymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiCashEntrypoint(addrs.entrypoint),
            ShinobiCashPool(addrs.ethPool),
            IShinobiInputSettler(addrs.inputSettler)
        );
        DeploymentWriter.writePaymaster(poolKey, "crossChain", address(pm), blockBefore);
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        console.log("   Address:", address(pm));
        console.log("   Block:", blockBefore);
    }

    function _deployWithdraw2Paymaster(
        string memory poolKey,
        DeploymentAddresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0)) {
            console.log("3. ShinobiNativeWithdraw2Paymaster already deployed:", existing);
            return;
        }
        console.log("3. Deploying ShinobiNativeWithdraw2Paymaster...");
        uint256 blockBefore = block.number;
        ShinobiNativeWithdraw2Paymaster pm = new ShinobiNativeWithdraw2Paymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiCashEntrypoint(addrs.entrypoint),
            IShinobiCashPool(addrs.ethPool),
            IWithdraw2Verifier(addrs.withdraw2Verifier)
        );
        DeploymentWriter.writePaymaster(poolKey, "withdraw2", address(pm), blockBefore);
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        console.log("   Address:", address(pm));
        console.log("   Block:", blockBefore);
    }

    function _deployCrosschainWithdraw2Paymaster(
        string memory poolKey,
        DeploymentAddresses memory addrs,
        address existing
    ) internal {
        if (existing != address(0)) {
            console.log("4. ShinobiNativeCrosschainWithdraw2Paymaster already deployed:", existing);
            return;
        }
        console.log("4. Deploying ShinobiNativeCrosschainWithdraw2Paymaster...");
        uint256 blockBefore = block.number;
        ShinobiNativeCrosschainWithdraw2Paymaster pm = new ShinobiNativeCrosschainWithdraw2Paymaster(
            IERC4337EntryPoint(addrs.erc4337Entrypoint),
            IShinobiCashEntrypoint(addrs.entrypoint),
            IShinobiCashPool(addrs.ethPool),
            ICrosschainWithdraw2Verifier(addrs.crossChainWithdraw2Verifier),
            IShinobiInputSettler(addrs.inputSettler)
        );
        DeploymentWriter.writePaymaster(poolKey, "crossChainWithdraw2", address(pm), blockBefore);
        pm.deposit{value: 0.01 ether}();
        pm.setExpectedSmartAccount(addrs.expectedSmartAccount);
        console.log("   Address:", address(pm));
        console.log("   Block:", blockBefore);
    }
}
