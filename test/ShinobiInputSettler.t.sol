// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ShinobiInputSettler} from "../src/oif/ShinobiInputSettler.sol";
import {IShinobiInputSettler} from "../src/oif/interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../src/oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../src/oif/libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

contract ShinobiInputSettlerTest is Test {
    using ShinobiIntentLib for ShinobiIntent;

    ShinobiInputSettler public settler;
    MockEntrypoint public entrypoint;
    MockFillOracle public fillOracle;

    address public user = makeAddr("user");
    address public solver = makeAddr("solver");
    address public intentOracle = makeAddr("intentOracle");
    address public outputSettler = makeAddr("outputSettler");

    uint256 public constant AMOUNT = 1 ether;

    event Open(bytes32 indexed orderId, ShinobiIntent intent);
    event Finalised(bytes32 indexed orderId, bytes32 solver, bytes32 destination);
    event Refunded(bytes32 indexed orderId);

    function setUp() public {
        fillOracle = new MockFillOracle();
        entrypoint = new MockEntrypoint();
        settler = new ShinobiInputSettler(address(entrypoint));
        entrypoint.setSettler(address(settler));

        vm.deal(address(entrypoint), 100 ether);
        vm.deal(solver, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public view {
        assertEq(settler.entrypoint(), address(entrypoint));
    }

    function test_constructor_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiInputSettler.InvalidEntrypoint.selector);
        new ShinobiInputSettler(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            OPEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_open_success() public {
        ShinobiIntent memory intent = _createValidIntent();
        bytes32 orderId = intent.orderIdentifier();

        vm.expectEmit(true, false, false, false);
        emit Open(orderId, intent);

        entrypoint.openIntent{value: AMOUNT}(intent);

        assertEq(uint256(settler.orderStatus(orderId)), uint256(IShinobiInputSettler.OrderStatus.Deposited));
    }

    function test_open_revertsUnauthorizedCaller() public {
        ShinobiIntent memory intent = _createValidIntent();
        vm.deal(user, AMOUNT);

        vm.expectRevert(ShinobiInputSettler.UnauthorizedCaller.selector);
        vm.prank(user);
        settler.open{value: AMOUNT}(intent);
    }

    function test_open_revertsInvalidChain() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.originChainId = block.chainid + 1;

        vm.expectRevert(ShinobiInputSettler.InvalidChain.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsDeadlinePassed() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.fillDeadline = uint32(block.timestamp - 1);

        vm.expectRevert(ShinobiInputSettler.DeadlinePassed.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsExpiryPassed() public {
        // Warp to a later time so we can set timestamps in the past
        vm.warp(1000);

        ShinobiIntent memory intent = _createValidIntent();
        intent.expires = uint32(block.timestamp - 1);
        intent.fillDeadline = uint32(block.timestamp - 2);

        vm.expectRevert(ShinobiInputSettler.DeadlinePassed.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsInvalidDeadlineOrder() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.expires = intent.fillDeadline; // expires must be > fillDeadline

        vm.expectRevert(ShinobiInputSettler.InvalidDeadlineOrder.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsEmptyInputs() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.inputs = new uint256[2][](0);

        vm.expectRevert(ShinobiInputSettler.InvalidIntent.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsEmptyOutputs() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs = new MandateOutput[](0);

        vm.expectRevert(ShinobiInputSettler.InvalidIntent.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsInvalidAsset() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.inputs[0][0] = 1; // Non-zero asset (not native ETH)

        vm.expectRevert(ShinobiInputSettler.InvalidAsset.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    function test_open_revertsInsufficientValue() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.expectRevert(ShinobiInputSettler.InvalidAmount.selector);
        entrypoint.openIntent{value: AMOUNT - 1}(intent);
    }

    function test_open_revertsAlreadyOpened() public {
        ShinobiIntent memory intent = _createValidIntent();

        entrypoint.openIntent{value: AMOUNT}(intent);

        vm.expectRevert(ShinobiInputSettler.InvalidOrderStatus.selector);
        entrypoint.openIntent{value: AMOUNT}(intent);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALISE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_finalise_success() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 orderId = intent.orderIdentifier();
        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        bytes32 destination = bytes32(uint256(uint160(solver)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        uint256 solverBalanceBefore = solver.balance;

        vm.expectEmit(true, false, false, true);
        emit Finalised(orderId, solverBytes, destination);

        vm.prank(solver);
        settler.finalise(intent, solveParams, destination);

        assertEq(uint256(settler.orderStatus(orderId)), uint256(IShinobiInputSettler.OrderStatus.Claimed));
        assertEq(solver.balance, solverBalanceBefore + AMOUNT);
    }

    function test_finalise_revertsNotDeposited() public {
        ShinobiIntent memory intent = _createValidIntent();
        bytes32 solverBytes = bytes32(uint256(uint160(solver)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        vm.expectRevert(ShinobiInputSettler.InvalidOrderStatus.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, solverBytes);
    }

    function test_finalise_revertsDeadlinePassed() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        // Warp past deadline
        vm.warp(intent.fillDeadline + 1);

        vm.expectRevert(ShinobiInputSettler.DeadlinePassed.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, solverBytes);
    }

    function test_finalise_revertsNotOrderOwner() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        // Different caller than solver
        vm.expectRevert(ShinobiInputSettler.NotOrderOwner.selector);
        vm.prank(user);
        settler.finalise(intent, solveParams, solverBytes);
    }

    function test_finalise_revertsMultipleSolvers() public {
        // Create intent with 2 outputs
        ShinobiIntent memory intent = _createValidIntent();
        MandateOutput[] memory outputs = new MandateOutput[](2);
        outputs[0] = intent.outputs[0];
        outputs[1] = _createValidOutput();
        intent.outputs = outputs;

        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solver1 = bytes32(uint256(uint160(solver)));
        bytes32 solver2 = bytes32(uint256(uint160(user)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](2);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solver1
        });
        solveParams[1] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solver2  // Different solver
        });

        vm.expectRevert(ShinobiInputSettler.MultipleSolversNotSupported.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, solver1);
    }

    function test_finalise_revertsInvalidSolveParamsLength() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));

        // 2 solve params for 1 output
        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](2);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });
        solveParams[1] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        vm.expectRevert(ShinobiInputSettler.InvalidSolveParamsLength.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, solverBytes);
    }

    function test_finalise_revertsFilledTooLate() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: intent.fillDeadline + 1, // Filled after deadline
            solver: solverBytes
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiInputSettler.FilledTooLate.selector,
                intent.fillDeadline,
                intent.fillDeadline + 1
            )
        );
        vm.prank(solver);
        settler.finalise(intent, solveParams, solverBytes);
    }

    function test_finalise_revertsDirtyBitsInDestination() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        // Destination with dirty upper bits
        bytes32 dirtyDestination = bytes32(uint256(uint160(solver)) | (uint256(1) << 160));

        vm.expectRevert(ShinobiInputSettler.DirtyUpperBits.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, dirtyDestination);
    }

    function test_finalise_revertsDirtyBitsInSolver() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        // Solver bytes with dirty upper bits
        bytes32 dirtySolverBytes = bytes32(uint256(uint160(solver)) | (uint256(1) << 200));
        bytes32 cleanDestination = bytes32(uint256(uint160(solver)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: dirtySolverBytes
        });

        vm.expectRevert(ShinobiInputSettler.DirtyUpperBits.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, cleanDestination);
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_refund_success() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 orderId = intent.orderIdentifier();

        // Warp past expiry
        vm.warp(intent.expires + 1);

        uint256 userBalanceBefore = user.balance;

        vm.expectEmit(true, false, false, false);
        emit Refunded(orderId);

        settler.refund(intent);

        assertEq(uint256(settler.orderStatus(orderId)), uint256(IShinobiInputSettler.OrderStatus.Refunded));
        assertEq(user.balance, userBalanceBefore + AMOUNT);
    }

    function test_refund_revertsNotDeposited() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.warp(intent.expires + 1);

        vm.expectRevert(ShinobiInputSettler.InvalidOrderStatus.selector);
        settler.refund(intent);
    }

    function test_refund_revertsExpiryNotReached() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        vm.expectRevert(ShinobiInputSettler.ExpiryNotReached.selector);
        settler.refund(intent);
    }

    function test_refund_revertsAlreadyRefunded() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        vm.warp(intent.expires + 1);
        settler.refund(intent);

        vm.expectRevert(ShinobiInputSettler.InvalidOrderStatus.selector);
        settler.refund(intent);
    }

    function test_refund_withCustomCalldata() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.refundCalldata = abi.encode(
            address(entrypoint),
            abi.encodeWithSelector(MockEntrypoint.handleRefund.selector, user)
        );

        entrypoint.openIntent{value: AMOUNT}(intent);
        vm.warp(intent.expires + 1);

        settler.refund(intent);

        assertEq(entrypoint.lastRefundAmount(), AMOUNT);
        assertEq(entrypoint.lastRefundRecipient(), user);
    }

    function test_refund_revertsInvalidRefundCalldataLength() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.refundCalldata = hex"0102030405"; // Less than 64 bytes

        entrypoint.openIntent{value: AMOUNT}(intent);
        vm.warp(intent.expires + 1);

        vm.expectRevert(ShinobiInputSettler.InvalidRefundCalldataLength.selector);
        settler.refund(intent);
    }

    function test_refund_revertsInvalidRefundTarget() public {
        ShinobiIntent memory intent = _createValidIntent();
        // Use an arbitrary address that is not the entrypoint
        intent.refundCalldata = abi.encode(makeAddr("attacker"), abi.encodeWithSelector(bytes4(0)));

        entrypoint.openIntent{value: AMOUNT}(intent);
        vm.warp(intent.expires + 1);

        vm.expectRevert(ShinobiInputSettler.InvalidRefundTarget.selector);
        settler.refund(intent);
    }

    /*//////////////////////////////////////////////////////////////
                        DIRTY BITS VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_bytes32ToAddress_validAddress() public {
        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        bytes32 destination = bytes32(uint256(uint160(solver)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        // Should succeed with clean bytes32
        vm.prank(solver);
        settler.finalise(intent, solveParams, destination);

        assertEq(uint256(settler.orderStatus(intent.orderIdentifier())), uint256(IShinobiInputSettler.OrderStatus.Claimed));
    }

    function testFuzz_bytes32ToAddress_revertsOnAnyDirtyBit(uint96 dirtyBits) public {
        vm.assume(dirtyBits > 0);

        ShinobiIntent memory intent = _createValidIntent();
        entrypoint.openIntent{value: AMOUNT}(intent);

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        // Set dirty bits in upper 96 bits
        bytes32 dirtyDestination = bytes32((uint256(dirtyBits) << 160) | uint256(uint160(solver)));

        IShinobiInputSettler.SolveParams[] memory solveParams = new IShinobiInputSettler.SolveParams[](1);
        solveParams[0] = IShinobiInputSettler.SolveParams({
            timestamp: uint32(block.timestamp),
            solver: solverBytes
        });

        vm.expectRevert(ShinobiInputSettler.DirtyUpperBits.selector);
        vm.prank(solver);
        settler.finalise(intent, solveParams, dirtyDestination);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_orderIdentifier_isConsistent() public view {
        ShinobiIntent memory intent = _createValidIntent();
        bytes32 id1 = settler.orderIdentifier(intent);
        bytes32 id2 = settler.orderIdentifier(intent);
        assertEq(id1, id2);
    }

    function test_orderIdentifier_differentForDifferentNonce() public view {
        ShinobiIntent memory intent1 = _createValidIntent();
        ShinobiIntent memory intent2 = _createValidIntent();
        intent2.nonce = 999;

        bytes32 id1 = settler.orderIdentifier(intent1);
        bytes32 id2 = settler.orderIdentifier(intent2);
        assertTrue(id1 != id2);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_receive_acceptsETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        (bool success,) = address(settler).call{value: amount}("");
        assertTrue(success);
        assertEq(address(settler).balance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createValidIntent() internal view returns (ShinobiIntent memory) {
        MandateOutput[] memory outputs = new MandateOutput[](1);
        outputs[0] = _createValidOutput();

        uint256[2][] memory inputs = new uint256[2][](1);
        inputs[0] = [uint256(0), AMOUNT];

        return ShinobiIntent({
            user: user,
            nonce: 1,
            originChainId: block.chainid,
            expires: uint32(block.timestamp + 1 days),
            fillDeadline: uint32(block.timestamp + 1 hours),
            fillOracle: address(fillOracle),
            inputs: inputs,
            outputs: outputs,
            intentOracle: intentOracle,
            refundCalldata: ""
        });
    }

    function _createValidOutput() internal view returns (MandateOutput memory) {
        return MandateOutput({
            oracle: bytes32(uint256(uint160(address(fillOracle)))),
            settler: bytes32(uint256(uint160(outputSettler))),
            chainId: block.chainid,
            token: bytes32(0),
            amount: AMOUNT,
            recipient: bytes32(uint256(uint160(user))),
            call: "",
            context: ""
        });
    }
}

/**
 * @notice Mock entrypoint that can call settler.open()
 */
contract MockEntrypoint {
    ShinobiInputSettler public settler;
    uint256 public lastRefundAmount;
    address public lastRefundRecipient;

    function setSettler(address _settler) external {
        settler = ShinobiInputSettler(payable(_settler));
    }

    function openIntent(ShinobiIntent calldata intent) external payable {
        settler.open{value: msg.value}(intent);
    }

    function handleRefund(address recipient) external payable {
        lastRefundAmount = msg.value;
        lastRefundRecipient = recipient;
    }

    receive() external payable {}
}

/**
 * @notice Mock fill oracle that always returns proven
 */
contract MockFillOracle {
    function efficientRequireProven(bytes calldata) external pure {
        // Always succeeds - proofs are valid
    }
}

/**
 * @notice Mock refund target for custom refund calldata tests
 */
contract MockRefundTarget {
    uint256 public lastAmount;
    address public lastRecipient;

    function handleRefund(address recipient) external payable {
        lastAmount = msg.value;
        lastRecipient = recipient;
    }

    receive() external payable {}
}
