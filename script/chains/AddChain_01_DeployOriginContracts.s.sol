// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Contracts to deploy
import {HyperlaneOracle} from "../../src/oif/hyperlane/HyperlaneOracle.sol";
import {ShinobiCrosschainDepositEntrypoint} from "../../src/core/ShinobiCrosschainDepositEntrypoint.sol";
import {ShinobiInputSettler} from "../../src/oif/ShinobiInputSettler.sol";
import {ShinobiWithdrawalOutputSettler} from "../../src/oif/ShinobiWithdrawalOutputSettler.sol";

/**
 * @title AddChain_01_DeployOriginContracts
 * @notice Deploy all required contracts on a new origin chain
 * @dev Run this script on the NEW origin chain (not pool chain)
 *
 * This script deploys:
 *   1. HyperlaneOracle - For cross-chain message relay
 *   2. ShinobiCrosschainDepositEntrypoint - User deposit interface
 *   3. ShinobiInputSettler - Escrows deposit funds
 *   4. ShinobiWithdrawalOutputSettler - Receives withdrawals from pool
 *
 * Input:  config/origins/{ORIGIN_KEY}.json
 * Output: deployments/{origin-name}.json
 *
 * Prerequisites:
 *   - Origin chain must be configured in script/config/origins/{ORIGIN_KEY}.json
 *   - Pool chain HyperlaneOracle must be deployed (in deployments/{pool-key}.json)
 *
 * Usage:
 *   ORIGIN_KEY=base-sepolia forge script script/chains/AddChain_01_DeployOriginContracts.s.sol \
 *     --rpc-url base-sepolia --broadcast --verify
 */
contract AddChain_01_DeployOriginContracts is Script {
    function run() external {
        string memory originKey = vm.envString("ORIGIN_KEY");

        // Load origin configuration
        ChainConfig.OriginConfig memory originConfig = ChainConfig.getOriginConfig(originKey);

        // Load pool configuration for HyperlaneOracle address
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(originConfig.poolKey);

        // Validate we're on the correct chain
        require(block.chainid == originConfig.chainId, "Wrong chain! Check RPC URL");

        // Read pool chain HyperlaneOracle from deployment file
        address poolHyperlaneOracle = DeploymentWriter.readContractAddress(originConfig.poolKey, "contracts", "hyperlaneOracle");
        require(poolHyperlaneOracle != address(0), "Pool chain HyperlaneOracle not deployed. Run pool deployment first.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory chainName = _sanitizeChainName(originConfig.name);

        // Check existing deployments
        address existingOracle = DeploymentWriter.readContractAddress(chainName, "contracts", "hyperlaneOracle");
        address existingDepositEntrypoint = DeploymentWriter.readContractAddress(chainName, "contracts", "depositEntrypoint");
        address existingInputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "inputSettler");
        address existingWithdrawalOutputSettler = DeploymentWriter.readContractAddress(chainName, "contracts", "withdrawalOutputSettler");

        // Check if all already deployed
        if (existingOracle != address(0) &&
            existingDepositEntrypoint != address(0) &&
            existingInputSettler != address(0) &&
            existingWithdrawalOutputSettler != address(0)) {
            console.log("All origin contracts already deployed:");
            console.log("  hyperlaneOracle:", existingOracle);
            console.log("  depositEntrypoint:", existingDepositEntrypoint);
            console.log("  inputSettler:", existingInputSettler);
            console.log("  withdrawalOutputSettler:", existingWithdrawalOutputSettler);
            console.log("");
            console.log("Skipping deployment.");
            return;
        }

        console.log("==========================================================");
        console.log("  ADD NEW CHAIN - Step 1: Deploy Origin Contracts");
        console.log("==========================================================");
        console.log("");
        console.log("Origin Key:", originKey);
        console.log("Chain:", originConfig.name);
        console.log("Chain ID:", originConfig.chainId);
        console.log("Deployer:", deployer);
        console.log("Output:", string.concat("deployments/", chainName, ".json"));
        console.log("");
        console.log("Pool Chain:", poolConfig.name);
        console.log("Pool HyperlaneOracle:", poolHyperlaneOracle);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Initialize deployment file for this chain if needed
        if (!DeploymentWriter.deploymentExists(chainName)) {
            DeploymentWriter.initDeployment(chainName, originConfig.chainId, deployer);
        }

        // 1. Deploy HyperlaneOracle
        address oracleAddr = existingOracle;
        if (existingOracle != address(0)) {
            console.log("1. HyperlaneOracle already deployed:", existingOracle);
        } else {
            console.log("1. Deploying HyperlaneOracle...");
            uint256 blockBefore = block.number;
            HyperlaneOracle oracle = new HyperlaneOracle(
                originConfig.hyperlaneMailbox,
                address(0), // Use default hook
                address(0)  // Use default ISM
            );
            oracleAddr = address(oracle);
            DeploymentWriter.writeContract(chainName, "hyperlaneOracle", oracleAddr, blockBefore);
            console.log("   Address:", oracleAddr);
            console.log("   Block:", blockBefore);
        }

        // 2. Deploy DepositEntrypoint
        address depositEntrypointAddr = existingDepositEntrypoint;
        if (existingDepositEntrypoint != address(0)) {
            console.log("2. DepositEntrypoint already deployed:", existingDepositEntrypoint);
        } else {
            console.log("2. Deploying ShinobiCrosschainDepositEntrypoint...");
            uint256 blockBefore = block.number;
            ShinobiCrosschainDepositEntrypoint depositEntrypoint = new ShinobiCrosschainDepositEntrypoint(deployer);
            depositEntrypointAddr = address(depositEntrypoint);
            DeploymentWriter.writeContract(chainName, "depositEntrypoint", depositEntrypointAddr, blockBefore);
            console.log("   Address:", depositEntrypointAddr);
            console.log("   Block:", blockBefore);
        }

        // 3. Deploy InputSettler (for deposit intents)
        if (existingInputSettler != address(0)) {
            console.log("3. InputSettler already deployed:", existingInputSettler);
        } else {
            console.log("3. Deploying ShinobiInputSettler...");
            uint256 blockBefore = block.number;
            ShinobiInputSettler inputSettler = new ShinobiInputSettler(depositEntrypointAddr);
            DeploymentWriter.writeContract(chainName, "inputSettler", address(inputSettler), blockBefore);
            console.log("   Address:", address(inputSettler));
            console.log("   Block:", blockBefore);
        }

        // 4. Deploy WithdrawalOutputSettler
        if (existingWithdrawalOutputSettler != address(0)) {
            console.log("4. WithdrawalOutputSettler already deployed:", existingWithdrawalOutputSettler);
        } else {
            console.log("4. Deploying ShinobiWithdrawalOutputSettler...");
            uint256 blockBefore = block.number;
            ShinobiWithdrawalOutputSettler withdrawalOutputSettler = new ShinobiWithdrawalOutputSettler(
                deployer,
                poolHyperlaneOracle // Fill oracle is HyperlaneOracle on pool chain
            );
            DeploymentWriter.writeContract(chainName, "withdrawalOutputSettler", address(withdrawalOutputSettler), blockBefore);
            console.log("   Address:", address(withdrawalOutputSettler));
            console.log("   Block:", blockBefore);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  DEPLOYMENT COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Deployment saved to:", string.concat("deployments/", chainName, ".json"));
        console.log("");
        console.log("Next steps:");
        console.log("1. ORIGIN_KEY=%s forge script AddChain_02_ConfigurePoolChain.s.sol --rpc-url <pool-chain>", originKey);
        console.log("2. ORIGIN_KEY=%s forge script AddChain_03_ConfigureOriginChain.s.sol --rpc-url <this-chain>", originKey);
    }

    function _sanitizeChainName(string memory name) internal pure returns (string memory) {
        bytes memory b = bytes(name);
        bytes memory result = new bytes(b.length);

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            if (char == 0x20) {
                result[i] = 0x2d;
            } else if (uint8(char) >= 65 && uint8(char) <= 90) {
                result[i] = bytes1(uint8(char) + 32);
            } else {
                result[i] = char;
            }
        }

        return string(result);
    }
}
