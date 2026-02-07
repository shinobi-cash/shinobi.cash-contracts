// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Paymasters - Standard 1:1 withdrawals
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/SimpleShinobiCashPoolPaymaster.sol";
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/CrossChainWithdrawalPaymaster.sol";

// Paymasters - Withdraw2 (2:1 withdrawals)
import {Withdraw2Paymaster} from "../src/paymaster/Withdraw2Paymaster.sol";
import {CrossChainWithdraw2Paymaster} from "../src/paymaster/CrossChainWithdraw2Paymaster.sol";

// Interfaces
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {ShinobiCashPool} from "../src/core/ShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrossChainWithdraw2Verifier} from "../src/core/interfaces/ICrossChainWithdraw2Verifier.sol";

/**
 * @title 13_DeployPaymasters
 * @notice Deploy ERC-4337 Paymasters for gas sponsorship
 * @dev Requires: SHINOBI_CASH_ENTRYPOINT_PROXY, SHINOBI_CASH_ETH_POOL, WITHDRAW2_VERIFIER, CROSSCHAIN_WITHDRAW2_VERIFIER env vars
 */
contract DeployPaymasters is Script {
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get addresses from previous deployments
        address entrypoint = vm.envAddress("SHINOBI_CASH_ENTRYPOINT_PROXY");
        address ethPool = vm.envAddress("SHINOBI_CASH_ETH_POOL");
        address withdraw2Verifier = vm.envAddress("WITHDRAW2_VERIFIER");
        address crossChainWithdraw2Verifier = vm.envAddress("CROSSCHAIN_WITHDRAW2_VERIFIER");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Step 13: Deploy Paymasters ===");
        console.log("Deployer:", deployer);
        console.log("ERC-4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("Shinobi Entrypoint:", entrypoint);
        console.log("ETH Pool:", ethPool);
        console.log("");

        // 1. Deploy Simple Privacy Pool Paymaster (1:1 same-chain)
        console.log("1. Deploying Simple Privacy Pool Paymaster (1:1 same-chain)...");
        address payable simplePaymaster = payable(address(new SimpleShinobiCashPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            IPrivacyPool(ethPool)
        )));
        console.log("   Simple Paymaster:", simplePaymaster);

        // 2. Deploy Cross-Chain Withdrawal Paymaster (1:1 cross-chain)
        console.log("2. Deploying Cross-Chain Withdrawal Paymaster (1:1 cross-chain)...");
        address payable crossChainPaymaster = payable(address(new CrossChainWithdrawalPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            ShinobiCashPool(ethPool)
        )));
        console.log("   Cross-Chain Paymaster:", crossChainPaymaster);

        // 3. Deploy Withdraw2 Paymaster (2:1 same-chain)
        console.log("3. Deploying Withdraw2 Paymaster (2:1 same-chain)...");
        address payable withdraw2Paymaster = payable(address(new Withdraw2Paymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        )));
        console.log("   Withdraw2 Paymaster:", withdraw2Paymaster);

        // 4. Deploy CrossChainWithdraw2 Paymaster (2:1 cross-chain)
        console.log("4. Deploying CrossChainWithdraw2 Paymaster (2:1 cross-chain)...");
        address payable crossChainWithdraw2Paymaster = payable(address(new CrossChainWithdraw2Paymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(entrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        )));
        console.log("   CrossChainWithdraw2 Paymaster:", crossChainWithdraw2Paymaster);

        // 5. Fund paymasters for gas sponsorship
        console.log("5. Funding Paymasters...");
        SimpleShinobiCashPoolPaymaster(simplePaymaster).deposit{value: 0.01 ether}();
        CrossChainWithdrawalPaymaster(crossChainPaymaster).deposit{value: 0.01 ether}();
        Withdraw2Paymaster(withdraw2Paymaster).deposit{value: 0.01 ether}();
        CrossChainWithdraw2Paymaster(crossChainWithdraw2Paymaster).deposit{value: 0.01 ether}();
        console.log("   Paymasters funded with 0.01 ETH each");

        // 6. Configure expected smart account (Rhinestone's Safe7579 factory default account)
        console.log("6. Configuring Expected Smart Account...");
        address expectedSmartAccount = 0xa3aBDC7f6334CD3EE466A115f30522377787c024;
        SimpleShinobiCashPoolPaymaster(simplePaymaster).setExpectedSmartAccount(expectedSmartAccount);
        CrossChainWithdrawalPaymaster(crossChainPaymaster).setExpectedSmartAccount(expectedSmartAccount);
        Withdraw2Paymaster(withdraw2Paymaster).setExpectedSmartAccount(expectedSmartAccount);
        CrossChainWithdraw2Paymaster(crossChainWithdraw2Paymaster).setExpectedSmartAccount(expectedSmartAccount);
        console.log("   Expected Smart Account set:", expectedSmartAccount);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Paymasters deployed and funded ===");
        console.log("SIMPLE_PAYMASTER=", simplePaymaster);
        console.log("CROSS_CHAIN_PAYMASTER=", crossChainPaymaster);
        console.log("WITHDRAW2_PAYMASTER=", withdraw2Paymaster);
        console.log("CROSSCHAIN_WITHDRAW2_PAYMASTER=", crossChainWithdraw2Paymaster);
        console.log("EXPECTED_SMART_ACCOUNT=", expectedSmartAccount);
    }
}
