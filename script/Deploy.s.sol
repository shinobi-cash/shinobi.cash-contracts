// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Shinobi Cash contracts
import {ShinobiCashEntrypoint} from "../src/contracts/ShinobiCashEntrypoint.sol";
import {ShinobiCashPoolSimple} from "../src/contracts/implementations/ShinobiCashPoolSimple.sol";
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/contracts/CrossChainWithdrawalPaymaster.sol";
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/contracts/SimpleShinobiCashPoolPaymaster.sol";
import {CrossChainWithdrawalVerifier} from "../src/paymaster/contracts/CrossChainWithdrawalVerifier.sol";
import {ExtendedInputSettler} from "../src/oif/contracts/ExtendedInputSettler.sol";

// Privacy Pools Core contracts (from submodule)
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";

// OpenZeppelin proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "../src/contracts/interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {IShinobiCashEntrypoint} from "../src/contracts/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashCrossChainHandler} from "../src/contracts/interfaces/IShinobiCashCrossChainHandler.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title Deploy
 * @notice E2E deployment script for Shinobi Cash cross-chain privacy pools
 * @dev Deploys complete cross-chain privacy pool infrastructure with account abstraction
 */
contract Deploy is Script {
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Shinobi Cash E2E Deployment ===");
        console.log("Deployer:", deployer);
        console.log("ERC-4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("");

        // 1. Deploy ZK Verifiers
        console.log("1. Deploying ZK Verifiers...");
        address withdrawalVerifier = address(new WithdrawalVerifier());
        address commitmentVerifier = address(new CommitmentVerifier());
        address crossChainVerifier = address(new CrossChainWithdrawalVerifier());
        
        console.log("   Withdrawal Verifier:", withdrawalVerifier);
        console.log("   Commitment Verifier:", commitmentVerifier);
        console.log("   Cross-Chain Verifier:", crossChainVerifier);

        // 2. Deploy Shinobi Cash Entrypoint with proxy (UUPS upgradeable)
        console.log("2. Deploying Shinobi Cash Entrypoint...");
        
        address shinobiEntrypoint = address(new ERC1967Proxy(
            address(new ShinobiCashEntrypoint()),
            abi.encodeWithSignature("initialize(address,address)", deployer, deployer)
        ));
        
        console.log("   Shinobi Cash Entrypoint:", shinobiEntrypoint);

        // 3. Deploy ETH Privacy Pool with cross-chain capabilities
        console.log("3. Deploying Shinobi ETH Privacy Pool...");
        address ethCashPool = address(new ShinobiCashPoolSimple(
            shinobiEntrypoint,
            withdrawalVerifier,
            commitmentVerifier,
            ICrossChainWithdrawalProofVerifier(crossChainVerifier)
        ));
        console.log("   Shinobi ETH Cash Pool:", ethCashPool);

        // 4. Register ETH Privacy Pool with Entrypoint
        console.log("4. Registering ETH Privacy Pool...");
        
        ShinobiCashEntrypoint(payable(shinobiEntrypoint)).registerPool(
            IERC20(Constants.NATIVE_ASSET), // ETH
            IPrivacyPool(ethCashPool),
            0.001 ether, // MIN_DEPOSIT (0.001 ETH)
            100, // VETTING_FEE_BPS (1%)
            1500 // MAX_RELAY_FEE_BPS (15%)
        );
        console.log("   ETH Pool registered with Shinobi Entrypoint");

        // 5. Deploy Extended OIF Input Settler
        console.log("5. Deploying Extended OIF Input Settler...");
        address extendedInputSettler = address(new ExtendedInputSettler());
        console.log("   Extended Input Settler:", extendedInputSettler);

        // 6. Configure cross-chain support
        console.log("6. Configuring cross-chain support...");
        ShinobiCashEntrypoint shinobiEntrypointContract = ShinobiCashEntrypoint(payable(shinobiEntrypoint));
        
        // Set Extended Input Settler
        shinobiEntrypointContract.setExtendedInputSettler(extendedInputSettler);
        console.log("   Extended Input Settler configured");
        
        // Enable supported chains (example: Ethereum mainnet, Arbitrum, Polygon)
        shinobiEntrypointContract.updateChainSupport(1, true);    // Ethereum
        shinobiEntrypointContract.updateChainSupport(42161, true); // Arbitrum
        shinobiEntrypointContract.updateChainSupport(137, true);   // Polygon
        console.log("   Cross-chain support enabled for: Ethereum, Arbitrum, Polygon");

        // 7. Deploy Cross-Chain Withdrawal Paymaster
        console.log("7. Deploying Cross-Chain Withdrawal Paymaster...");
        address payable crossChainPaymaster = payable(address(new CrossChainWithdrawalPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashCrossChainHandler(address(shinobiEntrypointContract)),
            IShinobiCashEntrypoint(address(shinobiEntrypointContract)),
            IPrivacyPool(ethCashPool)
        )));
        console.log("   Cross-Chain Paymaster deployed:", crossChainPaymaster);

        // 8. Deploy Simple Privacy Pool Paymaster
        console.log("8. Deploying Simple Privacy Pool Paymaster...");
        address payable simplePaymaster = payable(address(new SimpleShinobiCashPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IShinobiCashEntrypoint(address(shinobiEntrypointContract)),
            IPrivacyPool(ethCashPool)
        )));
        console.log("   Simple Paymaster deployed:", simplePaymaster);

        // 9. Fund paymasters for gas sponsorship
        console.log("9. Funding Paymasters...");
        CrossChainWithdrawalPaymaster(crossChainPaymaster).deposit{value: 0.1 ether}();
        SimpleShinobiCashPoolPaymaster(simplePaymaster).deposit{value: 0.1 ether}();
        console.log("   Paymasters funded with 0.1 ETH each");

        // 10. Verify deployment
        console.log("10. Verifying deployment...");
        require(crossChainPaymaster.code.length > 0, "Cross-chain paymaster deployment failed");
        require(simplePaymaster.code.length > 0, "Simple paymaster deployment failed");
        require(ethCashPool.code.length > 0, "Cash Pool deployment failed");
        require(shinobiEntrypoint.code.length > 0, "Entrypoint deployment failed");
        require(extendedInputSettler.code.length > 0, "Extended Input Settler deployment failed");
        console.log("   All contracts deployed successfully");

        vm.stopBroadcast();

        // Output addresses for integration scripts
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Copy these addresses to your integration scripts:");
        console.log("SHINOBI_ENTRYPOINT:", shinobiEntrypoint);
        console.log("PRIVACY_POOL:", ethCashPool); 
        console.log("CROSS_CHAIN_PAYMASTER:", crossChainPaymaster);
        console.log("SIMPLE_PAYMASTER:", simplePaymaster);
        console.log("EXTENDED_INPUT_SETTLER:", extendedInputSettler);
        console.log("WITHDRAWAL_VERIFIER:", withdrawalVerifier);
        console.log("COMMITMENT_VERIFIER:", commitmentVerifier);
        console.log("CROSS_CHAIN_VERIFIER:", crossChainVerifier);
        console.log("");
    }
}