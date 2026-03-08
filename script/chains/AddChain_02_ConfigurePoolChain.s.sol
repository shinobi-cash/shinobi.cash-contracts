// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

import {ShinobiDepositOutputSettler} from "../../src/oif/ShinobiDepositOutputSettler.sol";

/**
 * @title AddChain_02_ConfigurePoolChain
 * @notice Configure pool-chain contracts to accept deposits from a new origin chain
 * @dev Run this script on the POOL chain (e.g., Arbitrum Sepolia)
 *
 * Configures:
 *   - DepositOutputSettler.setOriginChainConfig() with origin chain's HyperlaneOracle + DepositEntrypoint
 *
 * Prerequisites:
 *   - Origin chain contracts deployed (AddChain_01)
 *   - Pool chain settlers deployed (Step 10)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia ORIGIN_KEY=base-sepolia \
 *     forge script script/chains/AddChain_02_ConfigurePoolChain.s.sol:AddChain_02_ConfigurePoolChain \
 *     --rpc-url arbitrum-sepolia --broadcast
 */
contract AddChain_02_ConfigurePoolChain is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        string memory originKey = vm.envString("ORIGIN_KEY");

        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);
        ChainConfig.OriginConfig memory originConfig = ChainConfig.getOriginConfig(originKey);

        require(block.chainid == poolConfig.chainId, "Must run on pool chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Read pool chain DepositOutputSettler
        address depositOutputSettler = DeploymentWriter.readContractAddress(poolKey, "contracts", "depositOutputSettler");
        require(depositOutputSettler != address(0), "DepositOutputSettler not deployed");

        // Read origin chain deployed addresses
        string memory originChainName = _sanitizeChainName(originConfig.name);
        address originHyperlaneOracle = DeploymentWriter.readContractAddress(originChainName, "contracts", "hyperlaneOracle");
        address originDepositEntrypoint = DeploymentWriter.readContractAddress(originChainName, "contracts", "depositEntrypoint");

        require(originHyperlaneOracle != address(0), "Origin HyperlaneOracle not deployed");
        require(originDepositEntrypoint != address(0), "Origin DepositEntrypoint not deployed");

        console.log("==========================================================");
        console.log("  ADD NEW CHAIN - Step 2: Configure Pool Chain");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Origin Key:", originKey);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("DepositOutputSettler:", depositOutputSettler);
        console.log("Origin Chain ID:", originConfig.chainId);
        console.log("Origin HyperlaneOracle:", originHyperlaneOracle);
        console.log("Origin DepositEntrypoint:", originDepositEntrypoint);
        console.log("");

        ShinobiDepositOutputSettler settler = ShinobiDepositOutputSettler(payable(depositOutputSettler));

        vm.startBroadcast(deployerPrivateKey);

        console.log("1. Configuring origin chain on DepositOutputSettler...");
        settler.setOriginChainConfig(
            originConfig.chainId,
            originHyperlaneOracle,
            originDepositEntrypoint
        );
        console.log("   Done.");

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  POOL CHAIN CONFIGURATION COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Next: ORIGIN_KEY=%s forge script AddChain_03_ConfigureOriginChain.s.sol --rpc-url <origin-chain>", originKey);
    }

    function _sanitizeChainName(string memory name) internal pure returns (string memory) {
        bytes memory b = bytes(name);
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            if (char == 0x20) result[i] = 0x2d;
            else if (uint8(char) >= 65 && uint8(char) <= 90) result[i] = bytes1(uint8(char) + 32);
            else result[i] = char;
        }
        return string(result);
    }
}
