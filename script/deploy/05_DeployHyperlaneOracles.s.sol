// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HyperlaneOracle} from "../src/oif/hyperlane/HyperlaneOracle.sol";

/**
 * @title 05_DeployHyperlaneOracles
 * @notice Deploy HyperlaneOracle contracts on Base Sepolia and Arbitrum Sepolia
 * @dev Run this script TWICE - once on each chain with the appropriate RPC URL
 * @dev IMPORTANT: Deploy these BEFORE scripts 06 and 09 (output settlers need oracle addresses)
 *
 * DEPLOYMENT:
 * ===========
 *
 * 1. Deploy on BASE SEPOLIA (origin chain):
 *    forge script script/05_DeployHyperlaneOracles.s.sol:DeployHyperlaneOracles \
 *      --rpc-url base-sepolia \
 *      --broadcast \
 *      --verify
 *
 * 2. Deploy on ARBITRUM SEPOLIA (destination chain):
 *    forge script script/05_DeployHyperlaneOracles.s.sol:DeployHyperlaneOracles \
 *      --rpc-url arbitrum-sepolia \
 *      --broadcast \
 *      --verify
 *
 * 3. Save deployed addresses to .env and continue with step 06
 *
 * HYPERLANE CONTRACT ADDRESSES:
 * =============================
 * Base Sepolia:
 *   - Mailbox: 0x6966b0E55883d49BFB24539356a2f8A673E02039
 *   - Domain ID: 84532
 *
 * Arbitrum Sepolia:
 *   - Mailbox: 0x598facE78a4302f11E3de0bee1894Da0b2Cb71F8
 *   - Domain ID: 421614
 */
contract DeployHyperlaneOracles is Script {
    // Hyperlane Mailbox addresses (verified from docs.hyperlane.xyz)
    address constant MAILBOX_BASE_SEPOLIA = 0x6966b0E55883d49BFB24539356a2f8A673E02039;
    address constant MAILBOX_ARBITRUM_SEPOLIA = 0x598facE78a4302f11E3de0bee1894Da0b2Cb71F8;

    // Hyperlane domain IDs
    uint32 constant DOMAIN_BASE_SEPOLIA = 84532;
    uint32 constant DOMAIN_ARBITRUM_SEPOLIA = 421614;

    // Chain IDs
    uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;
    uint256 constant CHAIN_ID_ARBITRUM_SEPOLIA = 421614;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;

        address mailbox;
        string memory chainName;

        if (chainId == CHAIN_ID_BASE_SEPOLIA) {
            mailbox = MAILBOX_BASE_SEPOLIA;
            chainName = "Base Sepolia";
        } else if (chainId == CHAIN_ID_ARBITRUM_SEPOLIA) {
            mailbox = MAILBOX_ARBITRUM_SEPOLIA;
            chainName = "Arbitrum Sepolia";
        } else {
            revert("Unsupported chain. Use Base Sepolia or Arbitrum Sepolia.");
        }

        console.log("=== Deploying HyperlaneOracle ===");
        console.log("Chain:", chainName);
        console.log("Chain ID:", chainId);
        console.log("Mailbox:", mailbox);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy HyperlaneOracle with:
        // - mailbox: Hyperlane Mailbox address for this chain
        // - customHook: address(0) = use default hook
        // - ism: address(0) = use default ISM
        HyperlaneOracle oracle = new HyperlaneOracle(mailbox, address(0), address(0));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("HyperlaneOracle deployed at:", address(oracle));
        console.log("");
        console.log("Next steps:");
        console.log("1. Deploy on the other chain if not done yet");
        console.log("2. Update .env with HYPERLANE_ORACLE_<CHAIN> addresses");
        console.log("3. Deploy DepositOutputSettler (step 06) and WithdrawalOutputSettler (step 09)");
        console.log("4. Run setup scripts (steps 10, 11, 12)");
    }
}
