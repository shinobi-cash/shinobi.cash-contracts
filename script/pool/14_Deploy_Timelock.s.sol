// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ChainConfig} from "../config/ChainConfig.sol";
import {DeploymentWriter} from "../config/DeploymentWriter.sol";
import {TimelockController} from "@oz/governance/TimelockController.sol";
import {IPoolDiamond} from "../../src/pool/interfaces/IPoolDiamond.sol";

/**
 * @title Deploy_Timelock
 * @notice Deploy TimelockController and transfer PoolDiamond admin to it
 *
 * Input:  deployments/{POOL_KEY}.json (needs poolDiamond address)
 * Output: deployments/{POOL_KEY}.json (writes timelock address)
 *
 * Env:
 *   POOL_KEY              - Pool config key (e.g., "arbitrum-sepolia")
 *   PRIVATE_KEY           - Deployer private key (must be current PoolDiamond admin)
 *   TIMELOCK_DELAY        - Delay in seconds (default: 48 hours)
 *   TIMELOCK_PROPOSER     - Proposer address (default: deployer)
 *   TIMELOCK_EXECUTOR     - Executor address (default: deployer)
 *
 * Usage:
 *   POOL_KEY=arbitrum-sepolia forge script script/pool/14_Deploy_Timelock.s.sol:Deploy_Timelock \
 *     --rpc-url arbitrum-sepolia --broadcast --verify
 */
contract Deploy_Timelock is Script {
    function run() external {
        string memory poolKey = vm.envString("POOL_KEY");
        ChainConfig.PoolConfig memory poolConfig = ChainConfig.getPoolConfig(poolKey);
        require(block.chainid == poolConfig.chainId, "Wrong chain!");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address diamondAddr = DeploymentWriter.readContractAddress(poolKey, "contracts", "poolDiamond");
        require(diamondAddr != address(0), "PoolDiamond not deployed");
        require(IPoolDiamond(diamondAddr).admin() == deployer, "Deployer is not current admin");

        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", uint256(48 hours));
        address proposer = vm.envOr("TIMELOCK_PROPOSER", deployer);
        address executorAddr = vm.envOr("TIMELOCK_EXECUTOR", deployer);

        _logHeader(poolKey, diamondAddr, minDelay, proposer, executorAddr);

        vm.startBroadcast(deployerPrivateKey);

        uint256 blockBefore = block.number;
        TimelockController timelock = _deployTimelock(proposer, executorAddr, deployer);
        _bootstrap(timelock, diamondAddr, minDelay, deployer);

        vm.stopBroadcast();

        DeploymentWriter.writeContract(poolKey, "timelock", address(timelock), blockBefore);
        _verify(IPoolDiamond(diamondAddr), timelock, minDelay, deployer);
    }

    function _deployTimelock(address proposer, address executorAddr, address bootstrapAdmin)
        internal
        returns (TimelockController)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executorAddr;

        TimelockController timelock = new TimelockController(0, proposers, executors, bootstrapAdmin);
        console.log("1. TimelockController deployed:", address(timelock));
        return timelock;
    }

    function _bootstrap(
        TimelockController timelock,
        address diamondAddr,
        uint256 minDelay,
        address deployer
    ) internal {
        // Transfer PoolDiamond admin to timelock
        IPoolDiamond(diamondAddr).transferAdmin(address(timelock));
        console.log("2. transferAdmin called (pending: timelock)");

        // Timelock accepts admin (delay=0, so immediate)
        bytes memory acceptData = abi.encodeCall(IPoolDiamond.acceptAdmin, ());
        bytes32 salt1 = keccak256("bootstrap-accept-admin");
        timelock.schedule(diamondAddr, 0, acceptData, bytes32(0), salt1, 0);
        timelock.execute(diamondAddr, 0, acceptData, bytes32(0), salt1);
        console.log("3. Timelock accepted admin of PoolDiamond");

        // Set the actual delay via self-call (delay=0, so immediate)
        bytes memory delayData = abi.encodeCall(TimelockController.updateDelay, (minDelay));
        bytes32 salt2 = keccak256("bootstrap-set-delay");
        timelock.schedule(address(timelock), 0, delayData, bytes32(0), salt2, 0);
        timelock.execute(address(timelock), 0, delayData, bytes32(0), salt2);
        console.log("4. Timelock delay set to:", minDelay, "seconds");

        // Renounce deployer's DEFAULT_ADMIN_ROLE on TimelockController
        bytes32 defaultAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        timelock.renounceRole(defaultAdminRole, deployer);
        console.log("5. Deployer renounced DEFAULT_ADMIN_ROLE");
    }

    function _verify(
        IPoolDiamond diamond,
        TimelockController timelock,
        uint256 minDelay,
        address deployer
    ) internal view {
        require(diamond.admin() == address(timelock), "Admin transfer failed");
        require(timelock.getMinDelay() == minDelay, "Delay not set");
        require(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer), "Admin role not renounced");

        console.log("");
        console.log("==========================================================");
        console.log("  TIMELOCK SETUP COMPLETE");
        console.log("==========================================================");
        console.log("PoolDiamond admin:", address(timelock));
        console.log("All admin calls require", minDelay, "second delay");
    }

    function _logHeader(
        string memory poolKey,
        address diamondAddr,
        uint256 minDelay,
        address proposer,
        address executorAddr
    ) internal pure {
        console.log("==========================================================");
        console.log("  Step 14: Timelock");
        console.log("==========================================================");
        console.log("Pool Key:", poolKey);
        console.log("Diamond:", diamondAddr);
        console.log("Min Delay:", minDelay, "seconds");
        console.log("Proposer:", proposer);
        console.log("Executor:", executorAddr);
        console.log("");
    }
}
