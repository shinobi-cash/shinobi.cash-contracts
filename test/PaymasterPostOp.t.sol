// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {ShinobiNativeWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeWithdrawalPaymaster.sol";
import {ShinobiNativeCrosschainWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdrawalPaymaster.sol";
import {ShinobiNativeWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeWithdraw2Paymaster.sol";
import {ShinobiNativeCrosschainWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdraw2Paymaster.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {ShinobiCashPool} from "../src/core/ShinobiCashPool.sol";

/**
 * @notice Mock ERC-4337 EntryPoint with depositTo function
 */
contract MockEntryPointWithDeposit {
    mapping(address => uint256) public deposits;

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    function depositTo(address account) external payable {
        deposits[account] += msg.value;
    }

    function getDeposit(address account) external view returns (uint256) {
        return deposits[account];
    }
}

/**
 * @notice Test harness to expose internal _postOp for ShinobiNativeWithdrawalPaymaster
 */
contract ShinobiNativeWithdrawalPaymasterHarness is ShinobiNativeWithdrawalPaymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IPrivacyPool _ethPrivacyPool
    ) ShinobiNativeWithdrawalPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethPrivacyPool) {}

    function exposed_postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }
}

/**
 * @notice Test harness to expose internal _postOp for ShinobiNativeCrosschainWithdrawalPaymaster
 */
contract ShinobiNativeCrosschainWithdrawalPaymasterHarness is ShinobiNativeCrosschainWithdrawalPaymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        ShinobiCashPool _ethShinobiCashPool
    ) ShinobiNativeCrosschainWithdrawalPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethShinobiCashPool) {}

    function exposed_postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }
}

/**
 * @notice Test harness to expose internal _postOp for ShinobiNativeWithdraw2Paymaster
 */
contract ShinobiNativeWithdraw2PaymasterHarness is ShinobiNativeWithdraw2Paymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        IWithdraw2Verifier _withdraw2Verifier
    ) ShinobiNativeWithdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _withdraw2Verifier) {}

    function exposed_postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }
}

/**
 * @notice Test harness to expose internal _postOp for ShinobiNativeCrosschainWithdraw2Paymaster
 */
contract ShinobiNativeCrosschainWithdraw2PaymasterHarness is ShinobiNativeCrosschainWithdraw2Paymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        ICrosschainWithdraw2Verifier _crosschainWithdraw2Verifier
    ) ShinobiNativeCrosschainWithdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _crosschainWithdraw2Verifier) {}

    function exposed_postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }
}

/**
 * @notice Recipient that tracks received ETH
 */
contract RefundRecipient {
    uint256 public receivedAmount;

    receive() external payable {
        receivedAmount += msg.value;
    }
}

contract PaymasterPostOpTest is Test {
    MockEntryPointWithDeposit public mockEntryPoint;
    address public shinobiCashEntrypoint = makeAddr("shinobiCashEntrypoint");
    address public ethPool = makeAddr("ethPool");
    address public withdraw2Verifier = makeAddr("withdraw2Verifier");
    address public crosschainWithdraw2Verifier = makeAddr("crosschainWithdraw2Verifier");

    ShinobiNativeWithdrawalPaymasterHarness public simplePaymaster;
    ShinobiNativeCrosschainWithdrawalPaymasterHarness public crosschainPaymaster;
    ShinobiNativeWithdraw2PaymasterHarness public withdraw2Paymaster;
    ShinobiNativeCrosschainWithdraw2PaymasterHarness public crosschainWithdraw2Paymaster;

    RefundRecipient public recipient;

    bytes32 public constant USER_OP_HASH = keccak256("userOpHash");
    uint256 public constant ACTUAL_GAS_COST = 50_000 gwei; // 50k gas at 1 gwei
    uint256 public constant FEE_PER_GAS = 1 gwei;
    uint256 public constant EXPECTED_FEE = 0.1 ether;

    event PrivacyPoolWithdrawalSponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
        bool success
    );

    event CrosschainWithdrawalSponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
        bool success
    );

    event Withdraw2Sponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
        bool success
    );

    event CrosschainWithdraw2Sponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
        bool success
    );

    function setUp() public {
        mockEntryPoint = new MockEntryPointWithDeposit();
        recipient = new RefundRecipient();

        simplePaymaster = new ShinobiNativeWithdrawalPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        crosschainPaymaster = new ShinobiNativeCrosschainWithdrawalPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        withdraw2Paymaster = new ShinobiNativeWithdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        crosschainWithdraw2Paymaster = new ShinobiNativeCrosschainWithdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrosschainWithdraw2Verifier(crosschainWithdraw2Verifier)
        );

        // Fund paymasters
        vm.deal(address(simplePaymaster), 10 ether);
        vm.deal(address(crosschainPaymaster), 10 ether);
        vm.deal(address(withdraw2Paymaster), 10 ether);
        vm.deal(address(crosschainWithdraw2Paymaster), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
            SIMPLE SHINOBI CASH POOL PAYMASTER POSTOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SimplePaymaster_postOp_successWithRefund() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = simplePaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);
        uint256 expectedRefund = EXPECTED_FEE - expectedActualCost;

        vm.expectEmit(true, true, false, true);
        emit PrivacyPoolWithdrawalSponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            expectedRefund,
            true
        );

        uint256 gasBefore = gasleft();
        simplePaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("SimplePaymaster postOp gas used:", gasUsed);

        // Check refund was sent to recipient
        assertEq(recipient.receivedAmount(), expectedRefund);

        // Check deposit was made to entryPoint
        assertEq(mockEntryPoint.getDeposit(address(simplePaymaster)), expectedActualCost);
    }

    function test_SimplePaymaster_postOp_failedNoRefund() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = simplePaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        vm.expectEmit(true, true, false, true);
        emit PrivacyPoolWithdrawalSponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            0, // No refund on failure
            false
        );

        uint256 gasBefore = gasleft();
        simplePaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opReverted,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("SimplePaymaster postOp (failed) gas used:", gasUsed);

        // No refund to recipient
        assertEq(recipient.receivedAmount(), 0);

        // Deposit still made
        assertEq(mockEntryPoint.getDeposit(address(simplePaymaster)), expectedActualCost);
    }

    function test_SimplePaymaster_postOp_noRefundWhenCostExceedsFee() public {
        uint256 postOpGasLimit = simplePaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);
        // Set expected fee lower than actual cost
        uint256 lowExpectedFee = expectedActualCost - 1;
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), lowExpectedFee);

        simplePaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );

        // No refund since expectedFee <= actualCost
        assertEq(recipient.receivedAmount(), 0);
    }

    /*//////////////////////////////////////////////////////////////
            CROSS CHAIN WITHDRAWAL PAYMASTER POSTOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crosschainPaymaster_postOp_success() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = crosschainPaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        vm.expectEmit(true, true, false, true);
        emit CrosschainWithdrawalSponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            0, // No refund in cross-chain version
            true
        );

        uint256 gasBefore = gasleft();
        crosschainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("CrosschainPaymaster postOp gas used:", gasUsed);

        // Cross-chain deposits expectedFeeAmount, not actualCost
        assertEq(mockEntryPoint.getDeposit(address(crosschainPaymaster)), EXPECTED_FEE);
    }

    function test_crosschainPaymaster_postOp_noDepositWhenZeroFee() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), 0);

        crosschainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );

        // No deposit when expectedFeeAmount is 0
        assertEq(mockEntryPoint.getDeposit(address(crosschainPaymaster)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                WITHDRAW2 PAYMASTER POSTOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeWithdraw2Paymaster_postOp_successWithRefund() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = withdraw2Paymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);
        uint256 expectedRefund = EXPECTED_FEE - expectedActualCost;

        vm.expectEmit(true, true, false, true);
        emit Withdraw2Sponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            expectedRefund,
            true
        );

        uint256 gasBefore = gasleft();
        withdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("ShinobiNativeWithdraw2Paymaster postOp gas used:", gasUsed);

        assertEq(recipient.receivedAmount(), expectedRefund);
        assertEq(mockEntryPoint.getDeposit(address(withdraw2Paymaster)), expectedActualCost);
    }

    function test_ShinobiNativeWithdraw2Paymaster_postOp_failedNoRefund() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = withdraw2Paymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        withdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opReverted,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );

        assertEq(recipient.receivedAmount(), 0);
        assertEq(mockEntryPoint.getDeposit(address(withdraw2Paymaster)), expectedActualCost);
    }

    /*//////////////////////////////////////////////////////////////
            CROSS CHAIN WITHDRAW2 PAYMASTER POSTOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShinobiNativeCrosschainWithdraw2Paymaster_postOp_success() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = crosschainWithdraw2Paymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        vm.expectEmit(true, true, false, true);
        emit CrosschainWithdraw2Sponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            0,
            true
        );

        uint256 gasBefore = gasleft();
        crosschainWithdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("ShinobiNativeCrosschainWithdraw2Paymaster postOp gas used:", gasUsed);

        assertEq(mockEntryPoint.getDeposit(address(crosschainWithdraw2Paymaster)), EXPECTED_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                    GAS MEASUREMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_measurePostOpGas_allPaymasters() public {
        // Measure each paymaster independently with fresh recipients

        // 1. SimplePaymaster (with refund path)
        RefundRecipient recipient1 = new RefundRecipient();
        bytes memory context1 = abi.encode(USER_OP_HASH, address(recipient1), EXPECTED_FEE);
        uint256 gasBefore = gasleft();
        simplePaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context1,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 simpleGas = gasBefore - gasleft();

        // 2. CrosschainPaymaster (no refund)
        RefundRecipient recipient2 = new RefundRecipient();
        bytes memory context2 = abi.encode(USER_OP_HASH, address(recipient2), EXPECTED_FEE);
        gasBefore = gasleft();
        crosschainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context2,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 crosschainGas = gasBefore - gasleft();

        // 3. ShinobiNativeWithdraw2Paymaster (with refund path)
        RefundRecipient recipient3 = new RefundRecipient();
        bytes memory context3 = abi.encode(USER_OP_HASH, address(recipient3), EXPECTED_FEE);
        gasBefore = gasleft();
        withdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context3,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 withdraw2Gas = gasBefore - gasleft();

        // 4. ShinobiNativeCrosschainWithdraw2Paymaster (no refund)
        RefundRecipient recipient4 = new RefundRecipient();
        bytes memory context4 = abi.encode(USER_OP_HASH, address(recipient4), EXPECTED_FEE);
        gasBefore = gasleft();
        crosschainWithdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context4,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 crosschainWithdraw2Gas = gasBefore - gasleft();

        console.log("=== PostOp Gas Usage ===");
        console.log("ShinobiNativeWithdrawalPaymaster:", simpleGas);
        console.log("ShinobiNativeCrosschainWithdrawalPaymaster:", crosschainGas);
        console.log("ShinobiNativeWithdraw2Paymaster:", withdraw2Gas);
        console.log("ShinobiNativeCrosschainWithdraw2Paymaster:", crosschainWithdraw2Gas);
    }

    function test_measurePostOpGas_withFailedRefund() public {
        // Create a contract that reverts on receive
        RevertingRecipient revertingRecipient = new RevertingRecipient();
        bytes memory context = abi.encode(USER_OP_HASH, address(revertingRecipient), EXPECTED_FEE);

        // This should still succeed even if refund fails
        uint256 gasBefore = gasleft();
        simplePaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("SimplePaymaster postOp with failed refund gas used:", gasUsed);

        // Deposit still made even if refund fails
        uint256 postOpGasLimit = simplePaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);
        assertEq(mockEntryPoint.getDeposit(address(simplePaymaster)), expectedActualCost);
    }
}

/**
 * @notice Recipient that reverts on receive
 */
contract RevertingRecipient {
    receive() external payable {
        revert("No refunds accepted");
    }
}
