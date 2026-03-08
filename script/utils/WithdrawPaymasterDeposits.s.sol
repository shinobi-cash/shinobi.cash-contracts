// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";

// Interface for paymaster withdrawal functions
interface IPaymasterWithdraw {
    function getDeposit() external view returns (uint256);
    function withdrawTo(address payable withdrawAddress, uint256 amount) external;
    function owner() external view returns (address);
}

/**
 * @title WithdrawPaymasterDeposits
 * @notice Withdraw all deposited funds from paymaster contracts
 * @dev Withdraws from ERC-4337 EntryPoint deposits for all paymasters
 *
 * Input:  deployments/{POOL_KEY}.json
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/utils/WithdrawPaymasterDeposits.s.sol:WithdrawPaymasterDeposits --rpc-url arbitrum-sepolia --broadcast
 */
contract WithdrawPaymasterDeposits is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);

        require(block.chainid == poolConfig.chainId, "Wrong chain! Check RPC URL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Read paymaster addresses from deployment file
        address simple = DeploymentWriter.readContractAddress(poolKey, "paymasters", "withdrawal");
        address crossChain = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crosschainWithdrawal");
        address withdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "withdraw2");
        address crossChainWithdraw2 = DeploymentWriter.readContractAddress(poolKey, "paymasters", "crosschainWithdraw2");

        console.log("==========================================================");
        console.log("  WITHDRAW PAYMASTER DEPOSITS");
        console.log("==========================================================");
        console.log("");
        console.log("Pool Key:", poolKey);
        console.log("Chain:", poolConfig.name);
        console.log("Deployer:", deployer);
        console.log("Withdraw To:", deployer);
        console.log("");

        uint256 totalWithdrawn = 0;

        vm.startBroadcast(deployerPrivateKey);

        // 1. Simple Paymaster
        if (simple != address(0)) {
            totalWithdrawn += _withdrawFromPaymaster("Simple", simple, deployer);
        } else {
            console.log("1. Simple Paymaster: Not deployed");
        }

        // 2. CrossChain Paymaster
        if (crossChain != address(0)) {
            totalWithdrawn += _withdrawFromPaymaster("CrossChain", crossChain, deployer);
        } else {
            console.log("2. CrossChain Paymaster: Not deployed");
        }

        // 3. Withdraw2 Paymaster
        if (withdraw2 != address(0)) {
            totalWithdrawn += _withdrawFromPaymaster("Withdraw2", withdraw2, deployer);
        } else {
            console.log("3. Withdraw2 Paymaster: Not deployed");
        }

        // 4. CrossChainWithdraw2 Paymaster
        if (crossChainWithdraw2 != address(0)) {
            totalWithdrawn += _withdrawFromPaymaster("CrossChainWithdraw2", crossChainWithdraw2, deployer);
        } else {
            console.log("4. CrossChainWithdraw2 Paymaster: Not deployed");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("  WITHDRAWAL COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Total Withdrawn:", totalWithdrawn, "wei");
        console.log("Total Withdrawn:", totalWithdrawn / 1e18, "ETH");
    }

    function _withdrawFromPaymaster(
        string memory name,
        address paymaster,
        address withdrawTo
    ) internal returns (uint256) {
        IPaymasterWithdraw pm = IPaymasterWithdraw(paymaster);

        // Check deposit balance
        uint256 deposit;
        try pm.getDeposit() returns (uint256 d) {
            deposit = d;
        } catch {
            console.log("  ", name, "Paymaster: Failed to read deposit");
            return 0;
        }

        if (deposit == 0) {
            console.log("  ", name, "Paymaster: No deposit to withdraw");
            return 0;
        }

        console.log("  ", name, "Paymaster:");
        console.log("    Address:", paymaster);
        console.log("    Deposit:", deposit, "wei");

        // Withdraw full amount
        try pm.withdrawTo(payable(withdrawTo), deposit) {
            console.log("    Withdrawn:", deposit, "wei");
            return deposit;
        } catch {
            console.log("    Failed to withdraw (not owner?)");
            return 0;
        }
    }
}
