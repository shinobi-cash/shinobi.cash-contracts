// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {TimelockController} from "@oz/governance/TimelockController.sol";
import {IPoolDiamond} from "../../../src/pool/interfaces/IPoolDiamond.sol";
import {IFacet} from "../../../src/pool/interfaces/IFacet.sol";
import {AccessControlOps} from "../../../src/pool/libraries/AccessControlOps.sol";
import {AccessControlStorageLib} from "../../../src/pool/storage/AccessControlStorage.sol";

contract TimelockTest is DiamondTestBase {
    TimelockController public timelock;

    address public proposer = makeAddr("proposer");
    address public executor = makeAddr("executor");
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    function setUp() public override {
        super.setUp();

        // OZ TimelockController uses timestamp=1 as DONE sentinel,
        // so we need block.timestamp > 1 for delay=0 scheduling to work
        vm.warp(1000);

        // Deploy timelock with minDelay=0 for bootstrap
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new TimelockController(0, proposers, executors, admin);

        // Transfer admin to timelock
        vm.prank(admin);
        pool.transferAdmin(address(timelock));

        // Accept admin via timelock (delay=0)
        bytes memory acceptData = abi.encodeCall(IPoolDiamond.acceptAdmin, ());
        bytes32 salt1 = keccak256("bootstrap-accept");
        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, acceptData, bytes32(0), salt1, 0);
        vm.prank(executor);
        timelock.execute(address(diamond), 0, acceptData, bytes32(0), salt1);

        // Set real delay
        bytes memory delayData = abi.encodeCall(TimelockController.updateDelay, (TIMELOCK_DELAY));
        bytes32 salt2 = keccak256("bootstrap-delay");
        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, delayData, bytes32(0), salt2, 0);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, delayData, bytes32(0), salt2);

        // Renounce admin's bootstrap role
        bytes32 defaultAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        timelock.renounceRole(defaultAdminRole, admin);
    }

    /*//////////////////////////////////////////////////////////////
                         HELPERS
    //////////////////////////////////////////////////////////////*/

    function _scheduleAndExecute(address target, bytes memory data, bytes32 salt) internal {
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, TIMELOCK_DELAY);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(executor);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    /*//////////////////////////////////////////////////////////////
                     VERIFY SETUP
    //////////////////////////////////////////////////////////////*/

    function test_setup_timelockIsAdmin() public view {
        assertEq(pool.admin(), address(timelock));
    }

    function test_setup_delayIsSet() public view {
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_setup_oldAdminCannotCall() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(admin);
        pool.setMaxSolverFeeBPS(100);
    }

    /*//////////////////////////////////////////////////////////////
              DIRECT CALLS REVERT (not via timelock)
    //////////////////////////////////////////////////////////////*/

    function test_directCall_setAssetConfig_reverts() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(proposer);
        pool.setAssetConfig(0.1 ether, 200, 1000);
    }

    function test_directCall_upgradeDiamond_reverts() public {
        address[] memory empty = new address[](0);
        IPoolDiamond.ReplaceAction[] memory emptyReplace = new IPoolDiamond.ReplaceAction[](0);

        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(proposer);
        pool.upgradeDiamond(empty, empty, emptyReplace);
    }

    function test_directCall_setWithdrawalInputSettler_reverts() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(proposer);
        pool.setWithdrawalInputSettler(makeAddr("settler"));
    }

    function test_directCall_windDown_reverts() public {
        vm.expectRevert(AccessControlOps.OnlyAdmin.selector);
        vm.prank(proposer);
        pool.windDown();
    }

    /*//////////////////////////////////////////////////////////////
              TIMELOCKED OPERATIONS WORK AFTER DELAY
    //////////////////////////////////////////////////////////////*/

    function test_timelocked_setAssetConfig() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setAssetConfig, (0.1 ether, 200, 1000));
        _scheduleAndExecute(address(diamond), data, keccak256("set-asset"));

        (uint256 minDep, uint256 vetting, uint256 maxRelay) = pool.assetConfig();
        assertEq(minDep, 0.1 ether);
        assertEq(vetting, 200);
        assertEq(maxRelay, 1000);
    }

    function test_timelocked_setMaxSolverFeeBPS() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (300));
        _scheduleAndExecute(address(diamond), data, keccak256("solver-fee"));

        assertEq(pool.maxSolverFeeBPS(), 300);
    }

    function test_timelocked_setMaxRefundFeeBPS() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxRefundFeeBPS, (300));
        _scheduleAndExecute(address(diamond), data, keccak256("refund-fee"));

        assertEq(pool.maxRefundFeeBPS(), 300);
    }

    function test_timelocked_setWithdrawalInputSettler() public {
        address newSettler = makeAddr("newSettler");
        bytes memory data = abi.encodeCall(IPoolDiamond.setWithdrawalInputSettler, (newSettler));
        _scheduleAndExecute(address(diamond), data, keccak256("w-settler"));

        assertEq(pool.withdrawalInputSettler(), newSettler);
    }

    function test_timelocked_setDepositOutputSettler() public {
        address newSettler = makeAddr("newSettler");
        bytes memory data = abi.encodeCall(IPoolDiamond.setDepositOutputSettler, (newSettler));
        _scheduleAndExecute(address(diamond), data, keccak256("d-settler"));

        assertEq(pool.depositOutputSettler(), newSettler);
    }

    function test_timelocked_setVettingFeeRecipient() public {
        address newRecipient = makeAddr("newVault");
        bytes memory data = abi.encodeCall(IPoolDiamond.setVettingFeeRecipient, (newRecipient));
        _scheduleAndExecute(address(diamond), data, keccak256("vetting"));

        assertEq(pool.vettingFeeRecipient(), newRecipient);
    }

    function test_timelocked_setWithdrawalChainConfig() public {
        address os = makeAddr("os");
        address oo = makeAddr("oo");
        address fo = makeAddr("fo");
        bytes memory data = abi.encodeCall(
            IPoolDiamond.setWithdrawalChainConfig, (84532, os, oo, fo, 3600, 7200)
        );
        _scheduleAndExecute(address(diamond), data, keccak256("chain-cfg"));

        (bool isConfigured,,,,,) = pool.withdrawalChainConfig(84532);
        assertTrue(isConfigured);
    }

    function test_timelocked_upgradeDiamond() public {
        MockTimelockFacet newFacet = new MockTimelockFacet();
        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IPoolDiamond.ReplaceAction[] memory replaceFacets = new IPoolDiamond.ReplaceAction[](0);

        bytes memory data = abi.encodeCall(IPoolDiamond.upgradeDiamond, (addFacets, removeFacets, replaceFacets));
        _scheduleAndExecute(address(diamond), data, keccak256("upgrade"));

        assertEq(pool.facetAddresses().length, 8);
    }

    function test_timelocked_windDown() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.windDown, ());
        _scheduleAndExecute(address(diamond), data, keccak256("winddown"));

        assertTrue(pool.dead());
    }

    function test_timelocked_grantRole() public {
        address newPostman = makeAddr("newPostman");
        bytes memory data = abi.encodeCall(
            IPoolDiamond.grantRole, (AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman)
        );
        _scheduleAndExecute(address(diamond), data, keccak256("grant"));

        assertTrue(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, newPostman));
    }

    function test_timelocked_revokeRole() public {
        bytes memory data = abi.encodeCall(
            IPoolDiamond.revokeRole, (AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman)
        );
        _scheduleAndExecute(address(diamond), data, keccak256("revoke"));

        assertFalse(pool.hasRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, aspPostman));
    }

    function test_timelocked_transferAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        bytes memory data = abi.encodeCall(IPoolDiamond.transferAdmin, (newAdmin));
        _scheduleAndExecute(address(diamond), data, keccak256("transfer"));

        assertEq(pool.pendingAdmin(), newAdmin);

        vm.prank(newAdmin);
        pool.acceptAdmin();
        assertEq(pool.admin(), newAdmin);
    }

    /*//////////////////////////////////////////////////////////////
                     EARLY EXECUTION REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_earlyExecution_reverts() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (300));
        bytes32 salt = keccak256("early");

        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, TIMELOCK_DELAY);

        // Try executing before delay
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(diamond), 0, data, bytes32(0), salt);
    }

    /*//////////////////////////////////////////////////////////////
                     CANCELLATION
    //////////////////////////////////////////////////////////////*/

    function test_cancel_preventsExecution() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (999));
        bytes32 salt = keccak256("cancel-test");
        bytes32 opId = timelock.hashOperation(address(diamond), 0, data, bytes32(0), salt);

        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, TIMELOCK_DELAY);
        assertTrue(timelock.isOperationPending(opId));

        // Cancel (proposer has CANCELLER_ROLE by default)
        vm.prank(proposer);
        timelock.cancel(opId);
        assertFalse(timelock.isOperation(opId));

        // Cannot execute after delay
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(diamond), 0, data, bytes32(0), salt);
    }

    /*//////////////////////////////////////////////////////////////
                     BATCH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function test_timelocked_batchOperation() public {
        address[] memory targets = new address[](2);
        targets[0] = address(diamond);
        targets[1] = address(diamond);

        uint256[] memory values = new uint256[](2);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (400));
        payloads[1] = abi.encodeCall(IPoolDiamond.setMaxRefundFeeBPS, (400));

        bytes32 salt = keccak256("batch");

        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, TIMELOCK_DELAY);

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        assertEq(pool.maxSolverFeeBPS(), 400);
        assertEq(pool.maxRefundFeeBPS(), 400);
    }

    /*//////////////////////////////////////////////////////////////
              UNAUTHORIZED SCHEDULE/EXECUTE REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_schedule_revertsForNonProposer() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (100));
        bytes32 salt = keccak256("unauth-sched");

        vm.expectRevert();
        vm.prank(user);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, TIMELOCK_DELAY);
    }

    function test_execute_revertsForNonExecutor() public {
        bytes memory data = abi.encodeCall(IPoolDiamond.setMaxSolverFeeBPS, (100));
        bytes32 salt = keccak256("unauth-exec");

        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, TIMELOCK_DELAY);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        vm.expectRevert();
        vm.prank(user);
        timelock.execute(address(diamond), 0, data, bytes32(0), salt);
    }
}

/*//////////////////////////////////////////////////////////////
                     MOCK FACET FOR UPGRADE TEST
//////////////////////////////////////////////////////////////*/

contract MockTimelockFacet is IFacet {
    function timelockTestFunction() external pure returns (uint256) {
        return 42;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.timelockTestFunction.selector);
    }
}
