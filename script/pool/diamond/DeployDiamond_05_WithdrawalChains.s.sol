// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../../config/ChainConfig.sol";
import {DeploymentWriter} from "../../config/DeploymentWriter.sol";

import {IPoolDiamond} from "../../../src/pool/interfaces/IPoolDiamond.sol";

/**
 * @title DeployDiamond_05_WithdrawalChains
 * @notice Configure withdrawal chain(s) on the PoolDiamond for cross-chain withdrawals
 *
 * Reads origin chain config for fillDeadline/expiry and deployed addresses for
 * outputSettler, outputFillOracle (from origin chain), and inputFillOracle (from pool chain).
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia ORIGIN_KEY=base-sepolia \
 *     forge script script/pool/diamond/DeployDiamond_05_WithdrawalChains.s.sol:DeployDiamond_05_WithdrawalChains \
 *     --rpc-url arbitrum-sepolia --broadcast
 */
contract DeployDiamond_05_WithdrawalChains is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        string memory originKey = vm.envString("ORIGIN_KEY");

        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);
        ChainConfig.OriginConfig memory originConfig = ChainConfig.getOriginConfig(originKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Must run on pool chain");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Read pool chain deployments
        address diamondAddr = DeploymentWriter.readContractAddress(poolKey, "contracts", "poolDiamond");
        address inputFillOracle = DeploymentWriter.readContractAddress(poolKey, "contracts", "hyperlaneOracle");

        require(diamondAddr != address(0), "PoolDiamond not deployed");
        require(inputFillOracle != address(0), "Pool chain HyperlaneOracle not deployed");

        // Read origin chain deployments
        address outputSettler = DeploymentWriter.readContractAddress(originKey, "contracts", "withdrawalOutputSettler");
        address outputFillOracle = DeploymentWriter.readContractAddress(originKey, "contracts", "hyperlaneOracle");

        require(outputSettler != address(0), "Origin WithdrawalOutputSettler not deployed");
        require(outputFillOracle != address(0), "Origin HyperlaneOracle not deployed");

        console.log("==========================================================");
        console.log("  DIAMOND SETUP - Step 5: Withdrawal Chain Config");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Origin Key:", originKey);
        console.log("Dest Chain ID:", originConfig.chainId);
        console.log("Diamond:", diamondAddr);
        console.log("");
        console.log("Output Settler:", outputSettler);
        console.log("Output Fill Oracle:", outputFillOracle);
        console.log("Input Fill Oracle:", inputFillOracle);
        console.log("Fill Deadline:", uint256(originConfig.fillDeadline));
        console.log("Expiry:", uint256(originConfig.expiry));
        console.log("");

        IPoolDiamond diamond = IPoolDiamond(diamondAddr);

        vm.startBroadcast(deployerPrivateKey);

        try diamond.setWithdrawalChainConfig(
            originConfig.chainId,
            outputSettler,
            outputFillOracle,
            inputFillOracle,
            originConfig.fillDeadline,
            originConfig.expiry
        ) {
            console.log("Withdrawal chain configured for chain", originConfig.chainId);
        } catch {
            console.log("Already configured or failed, skipping.");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  WITHDRAWAL CHAIN CONFIG COMPLETE");
        console.log("==========================================================");
    }
}
