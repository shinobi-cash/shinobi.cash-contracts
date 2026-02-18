// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ShinobiCashEntrypoint} from "../src/core/ShinobiCashEntrypoint.sol";
import {ShinobiCashCrosschainState} from "../src/core/ShinobiCashCrosschainState.sol";
import {IShinobiCashCrosschainHandler} from "../src/core/interfaces/IShinobiCashCrosschainHandler.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract ShinobiCashEntrypointTest is Test {
    ShinobiCashEntrypoint public entrypoint;
    ShinobiCashEntrypoint public implementation;

    address public owner = makeAddr("owner");
    address public postman = makeAddr("postman");
    address public user = makeAddr("user");
    address public withdrawalInputSettler = makeAddr("withdrawalInputSettler");
    address public depositOutputSettler = makeAddr("depositOutputSettler");
    address public outputSettler = makeAddr("outputSettler");
    address public outputOracle = makeAddr("outputOracle");
    address public fillOracle = makeAddr("fillOracle");

    uint256 public constant DESTINATION_CHAIN_ID = 84532; // Base Sepolia
    uint32 public constant FILL_DEADLINE = 3600; // 1 hour
    uint32 public constant EXPIRY = 86400; // 24 hours
    uint256 public constant MAX_SOLVER_FEE_BPS = 1000; // 10%

    // Role constants from parent
    bytes32 internal constant _OWNER_ROLE = keccak256("OWNER_ROLE");

    event WithdrawalInputSettlerUpdated(address indexed _previous, address indexed _new);
    event DepositOutputSettlerUpdated(address indexed _previous, address indexed _new);
    event MaxSolverFeeBPSUpdated(uint256 _previous, uint256 _new);
    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    );
    event CrosschainDeposited(
        address indexed _depositor,
        address indexed _pool,
        uint256 precommitment,
        uint256 _commitment,
        uint256 _amount
    );
    event Refunded(uint256 amount, uint256 indexed refundCommitmentHash);

    function setUp() public {
        // Deploy implementation
        implementation = new ShinobiCashEntrypoint();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            IEntrypoint.initialize.selector,
            owner,
            postman
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        entrypoint = ShinobiCashEntrypoint(payable(address(proxy)));

        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(depositOutputSettler, 100 ether);
        vm.deal(withdrawalInputSettler, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_success() public view {
        assertTrue(entrypoint.hasRole(_OWNER_ROLE, owner));
    }

    function test_initialize_revertsOnSecondCall() public {
        vm.expectRevert();
        entrypoint.initialize(owner, postman);
    }

    function test_initialize_revertsZeroOwner() public {
        ShinobiCashEntrypoint newImpl = new ShinobiCashEntrypoint();
        bytes memory initData = abi.encodeWithSelector(
            IEntrypoint.initialize.selector,
            address(0),
            postman
        );
        vm.expectRevert(IEntrypoint.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_initialize_revertsZeroPostman() public {
        ShinobiCashEntrypoint newImpl = new ShinobiCashEntrypoint();
        bytes memory initData = abi.encodeWithSelector(
            IEntrypoint.initialize.selector,
            owner,
            address(0)
        );
        vm.expectRevert(IEntrypoint.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    /*//////////////////////////////////////////////////////////////
                    SET WITHDRAWAL INPUT SETTLER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalInputSettler_success() public {
        vm.expectEmit(true, true, false, false);
        emit WithdrawalInputSettlerUpdated(address(0), withdrawalInputSettler);

        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        assertEq(entrypoint.withdrawalInputSettler(), withdrawalInputSettler);
    }

    function test_setWithdrawalInputSettler_revertsZeroAddress() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAddress.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(address(0));
    }

    function test_setWithdrawalInputSettler_onlyOwner() public {
        vm.expectRevert();
        vm.prank(user);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
    }

    function test_setWithdrawalInputSettler_canUpdateExisting() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        address newSettler = makeAddr("newSettler");

        vm.expectEmit(true, true, false, false);
        emit WithdrawalInputSettlerUpdated(withdrawalInputSettler, newSettler);

        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(newSettler);

        assertEq(entrypoint.withdrawalInputSettler(), newSettler);
    }

    /*//////////////////////////////////////////////////////////////
                    SET DEPOSIT OUTPUT SETTLER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setDepositOutputSettler_success() public {
        vm.expectEmit(true, true, false, false);
        emit DepositOutputSettlerUpdated(address(0), depositOutputSettler);

        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        assertEq(entrypoint.depositOutputSettler(), depositOutputSettler);
    }

    function test_setDepositOutputSettler_revertsZeroAddress() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAddress.selector);
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(address(0));
    }

    function test_setDepositOutputSettler_onlyOwner() public {
        vm.expectRevert();
        vm.prank(user);
        entrypoint.setDepositOutputSettler(depositOutputSettler);
    }

    function test_setDepositOutputSettler_canUpdateExisting() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        address newSettler = makeAddr("newSettler");

        vm.expectEmit(true, true, false, false);
        emit DepositOutputSettlerUpdated(depositOutputSettler, newSettler);

        vm.prank(owner);
        entrypoint.setDepositOutputSettler(newSettler);

        assertEq(entrypoint.depositOutputSettler(), newSettler);
    }

    /*//////////////////////////////////////////////////////////////
                    SET MAX SOLVER FEE BPS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMaxSolverFeeBPS_success() public {
        vm.expectEmit(false, false, false, true);
        emit MaxSolverFeeBPSUpdated(0, MAX_SOLVER_FEE_BPS);

        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        assertEq(entrypoint.maxSolverFeeBPS(), MAX_SOLVER_FEE_BPS);
    }

    function test_setMaxSolverFeeBPS_revertsWhenOver10000() public {
        vm.expectRevert(IEntrypoint.InvalidFeeBPS.selector);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(10001);
    }

    function test_setMaxSolverFeeBPS_allows10000() public {
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(10000);

        assertEq(entrypoint.maxSolverFeeBPS(), 10000);
    }

    function test_setMaxSolverFeeBPS_allowsZero() public {
        // First set a non-zero value
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(1000);

        // Then set to zero
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(0);

        assertEq(entrypoint.maxSolverFeeBPS(), 0);
    }

    function test_setMaxSolverFeeBPS_onlyOwner() public {
        vm.expectRevert();
        vm.prank(user);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);
    }

    function testFuzz_setMaxSolverFeeBPS_anyValidValue(uint256 feeBPS) public {
        vm.assume(feeBPS <= 10000);

        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(feeBPS);

        assertEq(entrypoint.maxSolverFeeBPS(), feeBPS);
    }

    function testFuzz_setMaxSolverFeeBPS_revertsInvalidValue(uint256 feeBPS) public {
        vm.assume(feeBPS > 10000);

        vm.expectRevert(IEntrypoint.InvalidFeeBPS.selector);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(feeBPS);
    }

    /*//////////////////////////////////////////////////////////////
                    SET WITHDRAWAL CHAIN CONFIG TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setWithdrawalChainConfig_success() public {
        vm.expectEmit(true, false, false, true);
        emit WithdrawalChainConfigured(
            DESTINATION_CHAIN_ID,
            FILL_DEADLINE,
            EXPIRY,
            outputSettler,
            outputOracle,
            fillOracle
        );

        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );

        (
            bool isConfigured,
            uint32 storedFillDeadline,
            uint32 storedExpiry,
            address storedOutputSettler,
            address storedOutputOracle,
            address storedFillOracle
        ) = entrypoint.withdrawalChainConfig(DESTINATION_CHAIN_ID);

        assertTrue(isConfigured);
        assertEq(storedFillDeadline, FILL_DEADLINE);
        assertEq(storedExpiry, EXPIRY);
        assertEq(storedOutputSettler, outputSettler);
        assertEq(storedOutputOracle, outputOracle);
        assertEq(storedFillOracle, fillOracle);
    }

    function test_setWithdrawalChainConfig_revertsZeroChainId() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidChainId.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            0,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_revertsZeroOutputSettler() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAddress.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            address(0),
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_revertsZeroOutputOracle() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAddress.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            address(0),
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_revertsZeroFillOracle() public {
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAddress.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            address(0),
            FILL_DEADLINE,
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_revertsFillDeadlineTooShort() public {
        vm.expectRevert(ShinobiCashCrosschainState.DeadlineTooShort.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            299, // Less than 300
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_revertsExpiryTooShort() public {
        vm.expectRevert(ShinobiCashCrosschainState.DeadlineTooShort.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            299 // Less than 300
        );
    }

    function test_setWithdrawalChainConfig_revertsExpiryNotAfterFillDeadline() public {
        vm.expectRevert(ShinobiCashCrosschainState.ExpiryBeforeFillDeadline.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            FILL_DEADLINE // Equal, not after
        );
    }

    function test_setWithdrawalChainConfig_revertsExpiryBeforeFillDeadline() public {
        vm.expectRevert(ShinobiCashCrosschainState.ExpiryBeforeFillDeadline.selector);
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            FILL_DEADLINE - 1 // Before fill deadline
        );
    }

    function test_setWithdrawalChainConfig_onlyOwner() public {
        vm.expectRevert();
        vm.prank(user);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );
    }

    function test_setWithdrawalChainConfig_canUpdateExisting() public {
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );

        address newOutputSettler = makeAddr("newOutputSettler");
        uint32 newFillDeadline = 7200;
        uint32 newExpiry = 172800;

        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            newOutputSettler,
            outputOracle,
            fillOracle,
            newFillDeadline,
            newExpiry
        );

        (
            bool isConfigured,
            uint32 storedFillDeadline,
            uint32 storedExpiry,
            address storedOutputSettler,
            ,
        ) = entrypoint.withdrawalChainConfig(DESTINATION_CHAIN_ID);

        assertTrue(isConfigured);
        assertEq(storedFillDeadline, newFillDeadline);
        assertEq(storedExpiry, newExpiry);
        assertEq(storedOutputSettler, newOutputSettler);
    }

    function test_setWithdrawalChainConfig_minimumValidDeadlines() public {
        // Exactly 300 for fillDeadline and 301 for expiry should work
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            300,
            301
        );

        (bool isConfigured, uint32 storedFillDeadline, uint32 storedExpiry, , , ) =
            entrypoint.withdrawalChainConfig(DESTINATION_CHAIN_ID);

        assertTrue(isConfigured);
        assertEq(storedFillDeadline, 300);
        assertEq(storedExpiry, 301);
    }

    /*//////////////////////////////////////////////////////////////
                        MODIFIER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyWithdrawalInputSettler_revertsUnauthorized() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        // Try to call handleRefund from unauthorized address
        vm.expectRevert(ShinobiCashCrosschainState.OnlyWithdrawalInputSettler.selector);
        vm.prank(user);
        entrypoint.handleRefund(12345, address(this), 0, 1);
    }

    function test_onlyDepositOutputSettler_revertsUnauthorized() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        // Try to call crosschainDeposit from unauthorized address
        vm.expectRevert(ShinobiCashCrosschainState.OnlyDepositOutputSettler.selector);
        vm.prank(user);
        entrypoint.crosschainDeposit{value: 1 ether}(user, 1 ether, 12345);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDeposit_revertsAmountMismatch() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        vm.expectRevert(IShinobiCashCrosschainHandler.AmountMismatch.selector);
        vm.prank(depositOutputSettler);
        entrypoint.crosschainDeposit{value: 0.5 ether}(user, 1 ether, 12345);
    }

    function test_crosschainDeposit_revertsPoolNotFound() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        // No pool registered for native asset
        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        vm.prank(depositOutputSettler);
        entrypoint.crosschainDeposit{value: 1 ether}(user, 1 ether, 12345);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN DEPOSIT ERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDepositERC20_revertsUnauthorized() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        address mockToken = makeAddr("mockToken");

        vm.expectRevert(ShinobiCashCrosschainState.OnlyDepositOutputSettler.selector);
        vm.prank(user);
        entrypoint.crosschainDepositERC20(IERC20(mockToken), user, 1 ether, 12345);
    }

    function test_crosschainDepositERC20_revertsInvalidAsset() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        // Cannot use native asset address with ERC20 function
        vm.expectRevert(ShinobiCashCrosschainState.InvalidAsset.selector);
        vm.prank(depositOutputSettler);
        entrypoint.crosschainDepositERC20(IERC20(Constants.NATIVE_ASSET), user, 1 ether, 12345);
    }

    function test_crosschainDepositERC20_revertsPoolNotFound() public {
        vm.prank(owner);
        entrypoint.setDepositOutputSettler(depositOutputSettler);

        address mockToken = makeAddr("mockToken");

        // No pool registered for the ERC20 token
        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        vm.prank(depositOutputSettler);
        entrypoint.crosschainDepositERC20(IERC20(mockToken), user, 1 ether, 12345);
    }

    /*//////////////////////////////////////////////////////////////
                        HANDLE REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_handleRefund_revertsPoolNotFound() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        // No pool registered for scope
        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        vm.prank(withdrawalInputSettler);
        entrypoint.handleRefund{value: 1 ether}(12345, address(this), 0, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crosschainWithdrawal_revertsWithdrawalInputSettlerNotSet() public {
        // Don't set withdrawal input settler
        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainProofLib.CrosschainWithdrawProof memory proof;

        vm.expectRevert(ShinobiCashCrosschainState.WithdrawalInputSettlerNotSet.selector);
        entrypoint.crosschainWithdrawal(withdrawal, proof, 1);
    }

    function test_crosschainWithdrawal_revertsMaxSolverFeeBPSNotSet() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        // Don't set maxSolverFeeBPS
        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainProofLib.CrosschainWithdrawProof memory proof;
        proof.pubSignals[3] = 1 ether; // withdrawnValue

        vm.expectRevert(ShinobiCashCrosschainState.MaxSolverFeeBPSNotSet.selector);
        entrypoint.crosschainWithdrawal(withdrawal, proof, 1);
    }

    function test_crosschainWithdrawal_revertsInvalidWithdrawalAmount() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainProofLib.CrosschainWithdrawProof memory proof;
        proof.pubSignals[3] = 0; // withdrawnValue = 0

        vm.expectRevert(IEntrypoint.InvalidWithdrawalAmount.selector);
        entrypoint.crosschainWithdrawal(withdrawal, proof, 1);
    }

    function test_crosschainWithdrawal_revertsInvalidProcessooor() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = user; // Wrong processooor
        CrosschainProofLib.CrosschainWithdrawProof memory proof;
        proof.pubSignals[5] = 1 ether; // withdrawnValue at index 5

        vm.expectRevert(IEntrypoint.InvalidProcessooor.selector);
        entrypoint.crosschainWithdrawal(withdrawal, proof, 1);
    }

    function test_crosschainWithdrawal_revertsPoolNotFound() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = address(entrypoint);
        CrosschainProofLib.CrosschainWithdrawProof memory proof;
        proof.pubSignals[5] = 1 ether; // withdrawnValue at index 5

        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        entrypoint.crosschainWithdrawal(withdrawal, proof, 999); // Unknown scope
    }

    /*//////////////////////////////////////////////////////////////
                        RELAY2 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_relay2_revertsInvalidWithdrawalAmount() public {
        IPrivacyPool.Withdrawal memory withdrawal;
        Withdraw2ProofLib.Withdraw2Proof memory proof;
        proof.pubSignals[3] = 0; // withdrawnValue = 0

        vm.expectRevert(IEntrypoint.InvalidWithdrawalAmount.selector);
        entrypoint.relay2(withdrawal, proof, 1);
    }

    function test_relay2_revertsInvalidProcessooor() public {
        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = user; // Wrong processooor
        Withdraw2ProofLib.Withdraw2Proof memory proof;
        proof.pubSignals[3] = 1 ether; // withdrawnValue

        vm.expectRevert(IEntrypoint.InvalidProcessooor.selector);
        entrypoint.relay2(withdrawal, proof, 1);
    }

    function test_relay2_revertsPoolNotFound() public {
        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = address(entrypoint);
        Withdraw2ProofLib.Withdraw2Proof memory proof;
        proof.pubSignals[3] = 1 ether; // withdrawnValue

        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        entrypoint.relay2(withdrawal, proof, 999); // Unknown scope
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAW2 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crossChainWithdrawal2_revertsWithdrawalInputSettlerNotSet() public {
        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof;

        vm.expectRevert(ShinobiCashCrosschainState.WithdrawalInputSettlerNotSet.selector);
        entrypoint.crossChainWithdrawal2(withdrawal, proof, 1);
    }

    function test_crossChainWithdrawal2_revertsMaxSolverFeeBPSNotSet() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);

        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof;
        proof.pubSignals[4] = 1 ether; // withdrawnValue

        vm.expectRevert(ShinobiCashCrosschainState.MaxSolverFeeBPSNotSet.selector);
        entrypoint.crossChainWithdrawal2(withdrawal, proof, 1);
    }

    function test_crossChainWithdrawal2_revertsInvalidWithdrawalAmount() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        IPrivacyPool.Withdrawal memory withdrawal;
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof;
        proof.pubSignals[4] = 0; // withdrawnValue = 0

        vm.expectRevert(IEntrypoint.InvalidWithdrawalAmount.selector);
        entrypoint.crossChainWithdrawal2(withdrawal, proof, 1);
    }

    function test_crossChainWithdrawal2_revertsInvalidProcessooor() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);

        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = user; // Wrong processooor
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof;
        proof.pubSignals[6] = 1 ether; // withdrawnValue at index 6

        vm.expectRevert(IEntrypoint.InvalidProcessooor.selector);
        entrypoint.crossChainWithdrawal2(withdrawal, proof, 1);
    }

    function test_crossChainWithdrawal2_revertsPoolNotFound() public {
        vm.prank(owner);
        entrypoint.setWithdrawalInputSettler(withdrawalInputSettler);
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);
        // Configure the destination chain
        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );

        // Create relay data with configured destination chain
        IShinobiCashCrosschainHandler.CrosschainRelayData memory relayData;
        relayData.feeRecipient = makeAddr("feeRecipient");
        relayData.solverFeeBPS = 100;
        // Pack chainId (32 bits) and recipient (160 bits) into encodedDestination
        relayData.encodedDestination = bytes32(uint256(DESTINATION_CHAIN_ID) << 224 | uint256(uint160(user)));

        IPrivacyPool.Withdrawal memory withdrawal;
        withdrawal.processooor = address(entrypoint);
        withdrawal.data = abi.encode(relayData);
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof;
        proof.pubSignals[6] = 1 ether; // withdrawnValue at index 6

        vm.expectRevert(IEntrypoint.PoolNotFound.selector);
        entrypoint.crossChainWithdrawal2(withdrawal, proof, 999); // Unknown scope
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawalChainConfig_returnsDefaultForUnconfigured() public view {
        (
            bool isConfigured,
            uint32 storedFillDeadline,
            uint32 storedExpiry,
            address storedOutputSettler,
            address storedOutputOracle,
            address storedFillOracle
        ) = entrypoint.withdrawalChainConfig(999999);

        assertFalse(isConfigured);
        assertEq(storedFillDeadline, 0);
        assertEq(storedExpiry, 0);
        assertEq(storedOutputSettler, address(0));
        assertEq(storedOutputOracle, address(0));
        assertEq(storedFillOracle, address(0));
    }

    function test_withdrawalInputSettler_initiallyZero() public view {
        assertEq(entrypoint.withdrawalInputSettler(), address(0));
    }

    function test_depositOutputSettler_initiallyZero() public view {
        assertEq(entrypoint.depositOutputSettler(), address(0));
    }

    function test_maxSolverFeeBPS_initiallyZero() public view {
        assertEq(entrypoint.maxSolverFeeBPS(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE ETH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_receive_revertsFromNonPool() public {
        // Native asset pool is not registered, so any ETH transfer should revert
        vm.prank(user);
        (bool success, bytes memory returnData) = address(entrypoint).call{value: 1 ether}("");
        assertFalse(success);
        // Verify the revert reason is NativeAssetNotAccepted
        assertEq(bytes4(returnData), IEntrypoint.NativeAssetNotAccepted.selector);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setWithdrawalChainConfig_variousChainIds(uint256 chainId) public {
        vm.assume(chainId > 0);

        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            chainId,
            outputSettler,
            outputOracle,
            fillOracle,
            FILL_DEADLINE,
            EXPIRY
        );

        (bool isConfigured, , , , , ) = entrypoint.withdrawalChainConfig(chainId);
        assertTrue(isConfigured);
    }

    function testFuzz_setWithdrawalChainConfig_variousDeadlines(
        uint32 fillDeadline,
        uint32 expiry
    ) public {
        vm.assume(fillDeadline >= 300);
        vm.assume(expiry > fillDeadline);

        vm.prank(owner);
        entrypoint.setWithdrawalChainConfig(
            DESTINATION_CHAIN_ID,
            outputSettler,
            outputOracle,
            fillOracle,
            fillDeadline,
            expiry
        );

        (
            bool isConfigured,
            uint32 storedFillDeadline,
            uint32 storedExpiry,
            ,
            ,
        ) = entrypoint.withdrawalChainConfig(DESTINATION_CHAIN_ID);

        assertTrue(isConfigured);
        assertEq(storedFillDeadline, fillDeadline);
        assertEq(storedExpiry, expiry);
    }
}

// Import proof libraries for type definitions
import {CrosschainProofLib} from "../src/core/libraries/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "../src/core/libraries/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "../src/core/libraries/CrosschainWithdraw2ProofLib.sol";
