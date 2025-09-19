// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Shinobi Cash contracts
import {ShinobiCashEntrypoint} from "../src/contracts/ShinobiCashEntrypoint.sol";
import {ShinobiCashPoolSimple} from "../src/contracts/implementations/ShinobiCashPoolSimple.sol";

// Privacy Pools Core verifiers
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";

// Shinobi verifier
import {CrossChainWithdrawalVerifier} from "../src/paymaster/contracts/CrossChainWithdrawalVerifier.sol";

// OpenZeppelin proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "../src/contracts/interfaces/ICrossChainWithdrawalProofVerifier.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title DeployShinobiCashInfrastructure
 * @notice Deployment script for core Shinobi Cash infrastructure on Arbitrum Sepolia
 * @dev Deploys verifiers, entrypoint, cash pool, and registers pool
 */
contract DeployShinobiCashInfrastructure is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Shinobi Cash Infrastructure Deployment ===");
        console.log("Deployer:", deployer);
        console.log("");

        // 1. Deploy ZK Verifiers
        console.log("1. Deploying ZK Verifiers...");
        address withdrawalVerifier = address(new WithdrawalVerifier());
        address commitmentVerifier = address(new CommitmentVerifier());
        address crossChainVerifier = address(new CrossChainWithdrawalVerifier());
        
        console.log("   Withdrawal Verifier:", withdrawalVerifier);
        console.log("   Commitment Verifier:", commitmentVerifier);
        console.log("   Cross-Chain Verifier:", crossChainVerifier);

        // 2. Deploy Shinobi Cash Entrypoint with UUPS proxy
        console.log("2. Deploying Shinobi Cash Entrypoint...");
        
        ShinobiCashEntrypoint implementation = new ShinobiCashEntrypoint();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature("initialize(address,address)", deployer, deployer)
        );
        address shinobiEntrypoint = address(proxy);
        
        console.log("   Implementation:", address(implementation));
        console.log("   Proxy (Entrypoint):", shinobiEntrypoint);

        // 3. Deploy Shinobi Cash Pool
        console.log("3. Deploying Shinobi Cash Pool...");
        address cashPool = address(new ShinobiCashPoolSimple(
            shinobiEntrypoint,
            withdrawalVerifier,
            commitmentVerifier,
            ICrossChainWithdrawalProofVerifier(crossChainVerifier)
        ));
        console.log("   Cash Pool:", cashPool);

        // 4. Register Cash Pool with Entrypoint
        console.log("4. Registering Cash Pool...");
        
        ShinobiCashEntrypoint entrypointContract = ShinobiCashEntrypoint(payable(shinobiEntrypoint));
        entrypointContract.registerPool(
            IERC20(Constants.NATIVE_ASSET), // ETH (address(0))
            IPrivacyPool(cashPool),
            0.0001 ether, // MIN_DEPOSIT (0.0001 ETH)
            10,          // VETTING_FEE_BPS (0.1%)
            1500         // MAX_RELAY_FEE_BPS (15%)
        );
        console.log("   Cash Pool registered with Entrypoint");

        vm.stopBroadcast();

        // 5. Summary
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("WITHDRAWAL_VERIFIER:", withdrawalVerifier);
        console.log("COMMITMENT_VERIFIER:", commitmentVerifier);
        console.log("CROSS_CHAIN_VERIFIER:", crossChainVerifier);
        console.log("ENTRYPOINT_IMPLEMENTATION:", address(implementation));
        console.log("ENTRYPOINT_PROXY:", shinobiEntrypoint);
        console.log("CASH_POOL:", cashPool);
        console.log("DEPLOYER:", deployer);
    }
}