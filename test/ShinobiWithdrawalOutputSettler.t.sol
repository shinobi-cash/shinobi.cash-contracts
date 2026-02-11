// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ShinobiWithdrawalOutputSettler} from "../src/oif/ShinobiWithdrawalOutputSettler.sol";
import {BaseShinobiOutputSettler} from "../src/oif/BaseShinobiOutputSettler.sol";
import {ShinobiIntent} from "../src/oif/libraries/ShinobiIntentType.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {IShinobiOutputSettler} from "../src/oif/interfaces/IShinobiOutputSettler.sol";

contract ShinobiWithdrawalOutputSettlerTest is Test {
    using MandateOutputEncodingLib for MandateOutput;

    ShinobiWithdrawalOutputSettler public settler;

    address public owner = makeAddr("owner");
    address public fillOracle = makeAddr("fillOracle");
    address public intentOracle = makeAddr("intentOracle");
    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");
    address public solver = makeAddr("solver");

    uint256 public constant AMOUNT = 1 ether;

    event OutputFilled(
        bytes32 indexed orderId,
        bytes32 solver,
        uint32 timestamp,
        MandateOutput output,
        uint256 finalAmount
    );

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        settler = new ShinobiWithdrawalOutputSettler(owner, fillOracle);
        vm.deal(solver, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public view {
        assertEq(settler.fillOracle(), fillOracle);
        assertEq(settler.owner(), owner);
    }

    function test_constructor_revertsZeroFillOracle() public {
        vm.expectRevert(ShinobiWithdrawalOutputSettler.InvalidFillOracle.selector);
        new ShinobiWithdrawalOutputSettler(owner, address(0));
    }

    function test_constructor_setsOwner() public view {
        assertEq(settler.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            FILL TESTS - SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_fill_success() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Verify fill record was created
        bytes32 orderId = _getOrderId(intent);
        bytes32 outputHash = _getOutputHash(intent.outputs[0]);
        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);
        assertTrue(fillRecord != bytes32(0), "Fill record should be created");
    }

    function test_fill_transfersETHToRecipient() public {
        ShinobiIntent memory intent = _createValidIntent();
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        assertEq(recipient.balance, recipientBalanceBefore + AMOUNT, "Recipient should receive ETH");
    }

    function test_fill_createsFillRecord() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = _getOrderId(intent);
        bytes32 outputHash = _getOutputHash(intent.outputs[0]);
        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);

        assertTrue(fillRecord != bytes32(0), "Fill record should exist");
    }

    function test_fill_marksPayloadAsValid() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Create the expected payload
        bytes32 orderId = _getOrderId(intent);
        bytes memory payload = settler.encodeFillPayload(
            solver,
            orderId,
            uint32(block.timestamp),
            intent.outputs[0]
        );

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        assertTrue(settler.arePayloadsValid(payloads), "Payload should be valid");
    }

    function test_fill_emitsOutputFilledEvent() public {
        ShinobiIntent memory intent = _createValidIntent();
        bytes32 orderId = _getOrderId(intent);

        vm.expectEmit(true, false, false, false);
        emit OutputFilled(
            orderId,
            bytes32(uint256(uint160(solver))),
            uint32(block.timestamp),
            intent.outputs[0],
            AMOUNT
        );

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    /*//////////////////////////////////////////////////////////////
                            FILL TESTS - REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_fill_revertsWhenZeroOutputs() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs = new MandateOutput[](0);

        vm.expectRevert(BaseShinobiOutputSettler.InvalidOutput.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenMultipleOutputs() public {
        ShinobiIntent memory intent = _createValidIntent();

        // Add second output
        MandateOutput[] memory outputs = new MandateOutput[](2);
        outputs[0] = intent.outputs[0];
        outputs[1] = _createValidOutput();
        intent.outputs = outputs;

        vm.expectRevert(BaseShinobiOutputSettler.InvalidOutput.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenWrongChain() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].chainId = block.chainid + 1; // Wrong chain

        vm.expectRevert(BaseShinobiOutputSettler.InvalidChain.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenFillDeadlinePassed() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.fillDeadline = uint32(block.timestamp - 1); // Past deadline

        vm.expectRevert(BaseShinobiOutputSettler.FillDeadlinePassed.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenFillOracleMismatch() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.fillOracle = makeAddr("wrongOracle"); // Wrong oracle

        vm.expectRevert(ShinobiWithdrawalOutputSettler.FillOracleMismatch.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenNonNativeToken() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].token = bytes32(uint256(uint160(makeAddr("token")))); // Non-native token

        vm.expectRevert(BaseShinobiOutputSettler.InvalidAsset.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenAlreadyFilled() public {
        ShinobiIntent memory intent = _createValidIntent();

        // First fill
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Second fill should revert
        vm.expectRevert(BaseShinobiOutputSettler.AlreadyFilled.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenInsufficientETH() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.expectRevert(BaseShinobiOutputSettler.ETHTransferFailed.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT - 1}(intent); // Insufficient ETH
    }

    /*//////////////////////////////////////////////////////////////
                        OWNABLE2STEP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership_setsPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        assertEq(settler.pendingOwner(), newOwner);
        assertEq(settler.owner(), owner); // Owner unchanged until accepted
    }

    function test_transferOwnership_onlyOwner() public {
        address newOwner = makeAddr("newOwner");
        address notOwner = makeAddr("notOwner");

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
        vm.prank(notOwner);
        settler.transferOwnership(newOwner);
    }

    function test_acceptOwnership_transfersOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        vm.prank(newOwner);
        settler.acceptOwnership();

        assertEq(settler.owner(), newOwner);
        assertEq(settler.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertsForNonPending() public {
        address newOwner = makeAddr("newOwner");
        address notPending = makeAddr("notPending");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notPending));
        vm.prank(notPending);
        settler.acceptOwnership();
    }

    function test_transferOwnership_emitsEvent() public {
        address newOwner = makeAddr("newOwner");

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(owner, newOwner);

        vm.prank(owner);
        settler.transferOwnership(newOwner);
    }

    function test_acceptOwnership_emitsEvent() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, newOwner);

        vm.prank(newOwner);
        settler.acceptOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getFillRecord_returnsCorrectRecord() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = _getOrderId(intent);
        bytes32 outputHash = _getOutputHash(intent.outputs[0]);
        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);

        // Fill record is keccak256(abi.encodePacked(solverBytes, timestamp))
        bytes32 expectedRecord = keccak256(
            abi.encodePacked(bytes32(uint256(uint160(solver))), uint32(block.timestamp))
        );
        assertEq(fillRecord, expectedRecord);
    }

    function test_getFillRecord_returnsZeroForUnfilled() public {
        bytes32 orderId = keccak256("nonexistent");
        bytes32 outputHash = keccak256("nonexistent");

        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);
        assertEq(fillRecord, bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                    IPAYLOADCREATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_arePayloadsValid_returnsTrueForValidPayloads() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = _getOrderId(intent);
        bytes memory payload = settler.encodeFillPayload(
            solver,
            orderId,
            uint32(block.timestamp),
            intent.outputs[0]
        );

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;

        assertTrue(settler.arePayloadsValid(payloads));
    }

    function test_arePayloadsValid_returnsFalseForInvalidPayloads() public {
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encode("invalid payload");

        assertFalse(settler.arePayloadsValid(payloads));
    }

    function test_arePayloadsValid_returnsTrueForEmptyArray() public {
        bytes[] memory payloads = new bytes[](0);
        assertTrue(settler.arePayloadsValid(payloads));
    }

    function test_arePayloadsValid_returnsFalseIfAnyInvalid() public {
        ShinobiIntent memory intent = _createValidIntent();

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = _getOrderId(intent);
        bytes memory validPayload = settler.encodeFillPayload(
            solver,
            orderId,
            uint32(block.timestamp),
            intent.outputs[0]
        );

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = validPayload;
        payloads[1] = abi.encode("invalid");

        assertFalse(settler.arePayloadsValid(payloads));
    }

    function test_encodeFillPayload_encodesCorrectly() public view {
        MandateOutput memory output = _createValidOutput();
        bytes32 orderId = keccak256("testOrder");
        uint32 timestamp = uint32(block.timestamp);

        bytes memory payload = settler.encodeFillPayload(solver, orderId, timestamp, output);

        // Payload should be non-empty
        assertTrue(payload.length > 0);
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
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fill_preventsReentrancy() public {
        // Deploy malicious recipient that tries to reenter
        ReentrantRecipient maliciousRecipient = new ReentrantRecipient(settler, fillOracle, intentOracle);
        vm.deal(address(maliciousRecipient), 100 ether);

        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].recipient = bytes32(uint256(uint160(address(maliciousRecipient))));

        // The fill will succeed, but the reentrant call inside receive() should fail
        // with ReentrancyGuardReentrantCall
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Verify the reentrant call was attempted and blocked
        assertTrue(maliciousRecipient.reentrancyBlocked(), "Reentrancy should have been blocked");
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_fill_withVariousAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        vm.deal(solver, amount);

        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].amount = amount;

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(solver);
        settler.fill{value: amount}(intent);

        assertEq(recipient.balance, recipientBalanceBefore + amount);
    }

    function testFuzz_fill_withVariousDeadlines(uint32 deadline) public {
        vm.assume(deadline > block.timestamp);

        ShinobiIntent memory intent = _createValidIntent();
        intent.fillDeadline = deadline;

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = _getOrderId(intent);
        bytes32 outputHash = _getOutputHash(intent.outputs[0]);
        assertTrue(settler.getFillRecord(orderId, outputHash) != bytes32(0));
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
            fillOracle: fillOracle,
            inputs: inputs,
            outputs: outputs,
            intentOracle: intentOracle,
            refundCalldata: ""
        });
    }

    function _createValidOutput() internal view returns (MandateOutput memory) {
        return MandateOutput({
            oracle: bytes32(uint256(uint160(fillOracle))),
            settler: bytes32(uint256(uint160(address(settler)))),
            chainId: block.chainid,
            token: bytes32(0), // Native ETH
            amount: AMOUNT,
            recipient: bytes32(uint256(uint160(recipient))),
            call: "",
            context: ""
        });
    }

    function _getOrderId(ShinobiIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                intent.user,
                intent.nonce,
                intent.originChainId,
                intent.expires,
                intent.fillDeadline,
                intent.fillOracle,
                keccak256(abi.encodePacked(intent.inputs)),
                keccak256(abi.encode(intent.outputs)),
                intent.intentOracle,
                keccak256(intent.refundCalldata)
            )
        );
    }

    /// @dev Helper to compute output hash for memory structs
    /// The library's getMandateOutputHash only works with calldata, so we use getMandateOutputHashMemory
    function _getOutputHash(MandateOutput memory output) internal pure returns (bytes32) {
        return MandateOutputEncodingLib.getMandateOutputHashMemory(output);
    }
}

/**
 * @notice Malicious contract that attempts reentrancy
 */
contract ReentrantRecipient {
    ShinobiWithdrawalOutputSettler public settler;
    address public fillOracle;
    address public intentOracle;
    bool public attacked;
    bool public reentrancyBlocked;

    constructor(
        ShinobiWithdrawalOutputSettler _settler,
        address _fillOracle,
        address _intentOracle
    ) {
        settler = _settler;
        fillOracle = _fillOracle;
        intentOracle = _intentOracle;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;

            // Create a different intent to attempt reentrancy
            MandateOutput[] memory outputs = new MandateOutput[](1);
            outputs[0] = MandateOutput({
                oracle: bytes32(uint256(uint160(fillOracle))),
                settler: bytes32(uint256(uint160(address(settler)))),
                chainId: block.chainid,
                token: bytes32(0),
                amount: msg.value,
                recipient: bytes32(uint256(uint160(address(this)))),
                call: "",
                context: ""
            });

            uint256[2][] memory inputs = new uint256[2][](1);
            inputs[0] = [uint256(0), msg.value];

            ShinobiIntent memory reentrantIntent = ShinobiIntent({
                user: address(this),
                nonce: 999, // Different nonce to create different order
                originChainId: block.chainid,
                expires: uint32(block.timestamp + 1 days),
                fillDeadline: uint32(block.timestamp + 1 hours),
                fillOracle: fillOracle,
                inputs: inputs,
                outputs: outputs,
                intentOracle: intentOracle,
                refundCalldata: ""
            });

            // Try to reenter - this should fail with ReentrancyGuardReentrantCall
            try settler.fill{value: msg.value}(reentrantIntent) {
                // If we get here, reentrancy wasn't blocked
                reentrancyBlocked = false;
            } catch {
                // Reentrancy was blocked
                reentrancyBlocked = true;
            }
        }
    }
}
