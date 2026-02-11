// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {SimpleShinobiCashPoolPaymaster} from "../src/paymaster/SimpleShinobiCashPoolPaymaster.sol";
import {CrossChainWithdrawalPaymaster} from "../src/paymaster/CrossChainWithdrawalPaymaster.sol";
import {Withdraw2Paymaster} from "../src/paymaster/Withdraw2Paymaster.sol";
import {CrossChainWithdraw2Paymaster} from "../src/paymaster/CrossChainWithdraw2Paymaster.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrossChainWithdraw2Verifier} from "../src/core/interfaces/ICrossChainWithdraw2Verifier.sol";
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
 * @notice Test harness to expose internal _postOp for SimpleShinobiCashPoolPaymaster
 */
contract SimpleShinobiCashPoolPaymasterHarness is SimpleShinobiCashPoolPaymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IPrivacyPool _ethPrivacyPool
    ) SimpleShinobiCashPoolPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethPrivacyPool) {}

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
 * @notice Test harness to expose internal _postOp for CrossChainWithdrawalPaymaster
 */
contract CrossChainWithdrawalPaymasterHarness is CrossChainWithdrawalPaymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        ShinobiCashPool _ethShinobiCashPool
    ) CrossChainWithdrawalPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethShinobiCashPool) {}

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
 * @notice Test harness to expose internal _postOp for Withdraw2Paymaster
 */
contract Withdraw2PaymasterHarness is Withdraw2Paymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        IWithdraw2Verifier _withdraw2Verifier
    ) Withdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _withdraw2Verifier) {}

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
 * @notice Test harness to expose internal _postOp for CrossChainWithdraw2Paymaster
 */
contract CrossChainWithdraw2PaymasterHarness is CrossChainWithdraw2Paymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        ICrossChainWithdraw2Verifier _crossChainWithdraw2Verifier
    ) CrossChainWithdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _crossChainWithdraw2Verifier) {}

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
    address public crossChainWithdraw2Verifier = makeAddr("crossChainWithdraw2Verifier");

    SimpleShinobiCashPoolPaymasterHarness public simplePaymaster;
    CrossChainWithdrawalPaymasterHarness public crossChainPaymaster;
    Withdraw2PaymasterHarness public withdraw2Paymaster;
    CrossChainWithdraw2PaymasterHarness public crossChainWithdraw2Paymaster;

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

    event CrossChainWithdrawalSponsored(
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

    event CrossChainWithdraw2Sponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded,
        bool success
    );

    function setUp() public {
        mockEntryPoint = new MockEntryPointWithDeposit();
        recipient = new RefundRecipient();

        simplePaymaster = new SimpleShinobiCashPoolPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IPrivacyPool(ethPool)
        );

        crossChainPaymaster = new CrossChainWithdrawalPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            ShinobiCashPool(ethPool)
        );

        withdraw2Paymaster = new Withdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            IWithdraw2Verifier(withdraw2Verifier)
        );

        crossChainWithdraw2Paymaster = new CrossChainWithdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(shinobiCashEntrypoint),
            IShinobiCashPool(ethPool),
            ICrossChainWithdraw2Verifier(crossChainWithdraw2Verifier)
        );

        // Fund paymasters
        vm.deal(address(simplePaymaster), 10 ether);
        vm.deal(address(crossChainPaymaster), 10 ether);
        vm.deal(address(withdraw2Paymaster), 10 ether);
        vm.deal(address(crossChainWithdraw2Paymaster), 10 ether);
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

    function test_CrossChainPaymaster_postOp_success() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = crossChainPaymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        vm.expectEmit(true, true, false, true);
        emit CrossChainWithdrawalSponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            0, // No refund in cross-chain version
            true
        );

        uint256 gasBefore = gasleft();
        crossChainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("CrossChainPaymaster postOp gas used:", gasUsed);

        // Cross-chain deposits expectedFeeAmount, not actualCost
        assertEq(mockEntryPoint.getDeposit(address(crossChainPaymaster)), EXPECTED_FEE);
    }

    function test_CrossChainPaymaster_postOp_noDepositWhenZeroFee() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), 0);

        crossChainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );

        // No deposit when expectedFeeAmount is 0
        assertEq(mockEntryPoint.getDeposit(address(crossChainPaymaster)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                WITHDRAW2 PAYMASTER POSTOP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw2Paymaster_postOp_successWithRefund() public {
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

        console.log("Withdraw2Paymaster postOp gas used:", gasUsed);

        assertEq(recipient.receivedAmount(), expectedRefund);
        assertEq(mockEntryPoint.getDeposit(address(withdraw2Paymaster)), expectedActualCost);
    }

    function test_Withdraw2Paymaster_postOp_failedNoRefund() public {
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

    function test_CrossChainWithdraw2Paymaster_postOp_success() public {
        bytes memory context = abi.encode(USER_OP_HASH, address(recipient), EXPECTED_FEE);

        uint256 postOpGasLimit = crossChainWithdraw2Paymaster.MIN_POST_OP_GAS_LIMIT();
        uint256 expectedActualCost = ACTUAL_GAS_COST + (postOpGasLimit * FEE_PER_GAS);

        vm.expectEmit(true, true, false, true);
        emit CrossChainWithdraw2Sponsored(
            address(recipient),
            USER_OP_HASH,
            expectedActualCost,
            0,
            true
        );

        uint256 gasBefore = gasleft();
        crossChainWithdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("CrossChainWithdraw2Paymaster postOp gas used:", gasUsed);

        assertEq(mockEntryPoint.getDeposit(address(crossChainWithdraw2Paymaster)), EXPECTED_FEE);
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

        // 2. CrossChainPaymaster (no refund)
        RefundRecipient recipient2 = new RefundRecipient();
        bytes memory context2 = abi.encode(USER_OP_HASH, address(recipient2), EXPECTED_FEE);
        gasBefore = gasleft();
        crossChainPaymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context2,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 crossChainGas = gasBefore - gasleft();

        // 3. Withdraw2Paymaster (with refund path)
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

        // 4. CrossChainWithdraw2Paymaster (no refund)
        RefundRecipient recipient4 = new RefundRecipient();
        bytes memory context4 = abi.encode(USER_OP_HASH, address(recipient4), EXPECTED_FEE);
        gasBefore = gasleft();
        crossChainWithdraw2Paymaster.exposed_postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context4,
            ACTUAL_GAS_COST,
            FEE_PER_GAS
        );
        uint256 crossChainWithdraw2Gas = gasBefore - gasleft();

        console.log("=== PostOp Gas Usage ===");
        console.log("SimpleShinobiCashPoolPaymaster:", simpleGas);
        console.log("CrossChainWithdrawalPaymaster:", crossChainGas);
        console.log("Withdraw2Paymaster:", withdraw2Gas);
        console.log("CrossChainWithdraw2Paymaster:", crossChainWithdraw2Gas);
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
