// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ShinobiDepositOutputSettler} from "../src/oif/ShinobiDepositOutputSettler.sol";
import {BaseShinobiOutputSettler} from "../src/oif/BaseShinobiOutputSettler.sol";
import {ShinobiIntent} from "../src/oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../src/oif/libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

contract ShinobiDepositOutputSettlerTest is Test {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    ShinobiDepositOutputSettler public settler;
    MockIntentOracle public intentOracle;
    MockDepositRecipient public depositRecipient;

    address public owner = makeAddr("owner");
    address public solver = makeAddr("solver");
    address public user = makeAddr("user");
    address public hyperlaneOracle = makeAddr("hyperlaneOracle");
    address public depositEntrypoint = makeAddr("depositEntrypoint");
    address public fillOracle = makeAddr("fillOracle");

    uint256 public constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia
    uint256 public constant AMOUNT = 1 ether;

    event OriginChainConfigSet(
        uint256 indexed chainId,
        address indexed hyperlaneOracle,
        address indexed depositEntrypoint
    );
    event OriginChainConfigRemoved(uint256 indexed chainId);
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
        intentOracle = new MockIntentOracle();
        settler = new ShinobiDepositOutputSettler(owner, address(intentOracle));
        depositRecipient = new MockDepositRecipient();

        // Configure origin chain
        vm.prank(owner);
        settler.setOriginChainConfig(ORIGIN_CHAIN_ID, hyperlaneOracle, depositEntrypoint);

        vm.deal(solver, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public view {
        assertEq(settler.intentOracle(), address(intentOracle));
        assertEq(settler.owner(), owner);
    }

    function test_constructor_revertsZeroIntentOracle() public {
        vm.expectRevert(ShinobiDepositOutputSettler.InvalidIntentOracle.selector);
        new ShinobiDepositOutputSettler(owner, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        OWNABLE2STEP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership_setsPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        assertEq(settler.pendingOwner(), newOwner);
        assertEq(settler.owner(), owner);
    }

    function test_acceptOwnership_transfersOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        vm.prank(newOwner);
        settler.acceptOwnership();

        assertEq(settler.owner(), newOwner);
    }

    function test_acceptOwnership_revertsForNonPending() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        settler.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        settler.acceptOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                    ORIGIN CHAIN CONFIG TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setOriginChainConfig_success() public {
        uint256 newChainId = 421614;
        address newHyperlaneOracle = makeAddr("newHyperlaneOracle");
        address newEntrypoint = makeAddr("newEntrypoint");

        vm.expectEmit(true, true, true, false);
        emit OriginChainConfigSet(newChainId, newHyperlaneOracle, newEntrypoint);

        vm.prank(owner);
        settler.setOriginChainConfig(newChainId, newHyperlaneOracle, newEntrypoint);

        (address storedOracle, address storedEntrypoint, bool isConfigured) =
            settler.originChainConfigs(newChainId);

        assertEq(storedOracle, newHyperlaneOracle);
        assertEq(storedEntrypoint, newEntrypoint);
        assertTrue(isConfigured);
    }

    function test_setOriginChainConfig_revertsZeroChainId() public {
        vm.expectRevert(ShinobiDepositOutputSettler.InvalidChainId.selector);
        vm.prank(owner);
        settler.setOriginChainConfig(0, hyperlaneOracle, depositEntrypoint);
    }

    function test_setOriginChainConfig_revertsZeroHyperlaneOracle() public {
        vm.expectRevert(ShinobiDepositOutputSettler.InvalidAddress.selector);
        vm.prank(owner);
        settler.setOriginChainConfig(ORIGIN_CHAIN_ID, address(0), depositEntrypoint);
    }

    function test_setOriginChainConfig_revertsZeroEntrypoint() public {
        vm.expectRevert(ShinobiDepositOutputSettler.InvalidAddress.selector);
        vm.prank(owner);
        settler.setOriginChainConfig(ORIGIN_CHAIN_ID, hyperlaneOracle, address(0));
    }

    function test_setOriginChainConfig_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        settler.setOriginChainConfig(ORIGIN_CHAIN_ID, hyperlaneOracle, depositEntrypoint);
    }

    function test_removeOriginChainConfig_success() public {
        vm.expectEmit(true, false, false, false);
        emit OriginChainConfigRemoved(ORIGIN_CHAIN_ID);

        vm.prank(owner);
        settler.removeOriginChainConfig(ORIGIN_CHAIN_ID);

        (, , bool isConfigured) = settler.originChainConfigs(ORIGIN_CHAIN_ID);
        assertFalse(isConfigured);
    }

    function test_removeOriginChainConfig_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        settler.removeOriginChainConfig(ORIGIN_CHAIN_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            FILL TESTS - SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_fill_success() public {
        ShinobiIntent memory intent = _createValidIntent();

        // Set up oracle to return proven
        intentOracle.setProven(true);

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Verify callback was executed
        assertTrue(depositRecipient.depositCalled());
        assertEq(depositRecipient.lastAmount(), AMOUNT);
    }

    function test_fill_emitsEvent() public {
        ShinobiIntent memory intent = _createValidIntent();
        bytes32 orderId = intent.orderIdentifier();

        intentOracle.setProven(true);

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

        intentOracle.setProven(true);

        vm.expectRevert(BaseShinobiOutputSettler.InvalidOutput.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenMultipleOutputs() public {
        ShinobiIntent memory intent = _createValidIntent();
        MandateOutput[] memory outputs = new MandateOutput[](2);
        outputs[0] = intent.outputs[0];
        outputs[1] = _createValidOutput();
        intent.outputs = outputs;

        intentOracle.setProven(true);

        vm.expectRevert(BaseShinobiOutputSettler.InvalidOutput.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenWrongChain() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].chainId = block.chainid + 1;

        intentOracle.setProven(true);

        vm.expectRevert(BaseShinobiOutputSettler.InvalidChain.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenFillDeadlinePassed() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.fillDeadline = uint32(block.timestamp - 1);

        intentOracle.setProven(true);

        vm.expectRevert(BaseShinobiOutputSettler.FillDeadlinePassed.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenIntentOracleMismatch() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.intentOracle = makeAddr("wrongOracle");

        intentOracle.setProven(true);

        vm.expectRevert(ShinobiDepositOutputSettler.IntentOracleMismatch.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenOriginChainNotConfigured() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.originChainId = 999999; // Unconfigured chain

        intentOracle.setProven(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiDepositOutputSettler.OriginChainNotConfigured.selector,
                999999
            )
        );
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenIntentNotProven() public {
        ShinobiIntent memory intent = _createValidIntent();

        // Oracle returns not proven
        intentOracle.setProven(false);

        vm.expectRevert(ShinobiDepositOutputSettler.IntentNotProven.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenEmptyCallbackData() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].call = ""; // Empty callback

        intentOracle.setProven(true);

        vm.expectRevert(ShinobiDepositOutputSettler.EmptyCallbackData.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenCallbackFails() public {
        ShinobiIntent memory intent = _createValidIntent();

        // Use a recipient that will fail
        FailingRecipient failingRecipient = new FailingRecipient();
        intent.outputs[0].recipient = bytes32(uint256(uint160(address(failingRecipient))));

        intentOracle.setProven(true);

        vm.expectRevert(ShinobiDepositOutputSettler.CallbackFailed.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenZeroValueWithAccumulatedBalance() public {
        vm.deal(address(settler), 10 ether);

        ShinobiIntent memory intent = _createValidIntent();
        intentOracle.setProven(true);

        vm.expectRevert(ShinobiDepositOutputSettler.InsufficientFillValue.selector);
        vm.prank(solver);
        settler.fill{value: 0}(intent);
    }

    function test_fill_revertsWhenAlreadyFilled() public {
        ShinobiIntent memory intent = _createValidIntent();
        intentOracle.setProven(true);

        // First fill
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        // Second fill should revert
        vm.expectRevert(BaseShinobiOutputSettler.AlreadyFilled.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    function test_fill_revertsWhenNonNativeToken() public {
        ShinobiIntent memory intent = _createValidIntent();
        intent.outputs[0].token = bytes32(uint256(uint160(makeAddr("token"))));

        intentOracle.setProven(true);

        vm.expectRevert(BaseShinobiOutputSettler.InvalidAsset.selector);
        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getFillRecord_returnsCorrectRecord() public {
        ShinobiIntent memory intent = _createValidIntent();
        intentOracle.setProven(true);

        vm.prank(solver);
        settler.fill{value: AMOUNT}(intent);

        bytes32 orderId = intent.orderIdentifier();
        bytes32 outputHash = _getOutputHash(intent.outputs[0]);
        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);

        assertTrue(fillRecord != bytes32(0));
    }

    function test_getFillRecord_returnsZeroForUnfilled() public view {
        bytes32 orderId = keccak256("nonexistent");
        bytes32 outputHash = keccak256("nonexistent");

        bytes32 fillRecord = settler.getFillRecord(orderId, outputHash);
        assertEq(fillRecord, bytes32(0));
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
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setOriginChainConfig_variousChainIds(uint256 chainId) public {
        vm.assume(chainId > 0 && chainId < type(uint256).max);

        vm.prank(owner);
        settler.setOriginChainConfig(chainId, hyperlaneOracle, depositEntrypoint);

        (address storedOracle, , bool isConfigured) = settler.originChainConfigs(chainId);
        assertEq(storedOracle, hyperlaneOracle);
        assertTrue(isConfigured);
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
            originChainId: ORIGIN_CHAIN_ID,
            expires: uint32(block.timestamp + 1 days),
            fillDeadline: uint32(block.timestamp + 1 hours),
            fillOracle: fillOracle,
            inputs: inputs,
            outputs: outputs,
            intentOracle: address(intentOracle),
            refundCalldata: ""
        });
    }

    function _createValidOutput() internal view returns (MandateOutput memory) {
        // Create callback data for crosschainDeposit
        bytes memory callbackData = abi.encodeWithSignature(
            "crosschainDeposit(address,uint256,uint256)",
            user,
            AMOUNT,
            12345 // precommitment
        );

        return MandateOutput({
            oracle: bytes32(uint256(uint160(address(intentOracle)))),
            settler: bytes32(uint256(uint160(address(settler)))),
            chainId: block.chainid,
            token: bytes32(0), // Native ETH
            amount: AMOUNT,
            recipient: bytes32(uint256(uint160(address(depositRecipient)))),
            call: callbackData,
            context: ""
        });
    }

    function _getOutputHash(MandateOutput memory output) internal pure returns (bytes32) {
        return MandateOutputEncodingLib.getMandateOutputHashMemory(output);
    }
}

/**
 * @notice Mock intent oracle for testing
 */
contract MockIntentOracle {
    bool public provenResult;

    function setProven(bool _proven) external {
        provenResult = _proven;
    }

    function isProven(
        uint256,
        bytes32,
        bytes32,
        bytes32
    ) external view returns (bool) {
        return provenResult;
    }
}

/**
 * @notice Mock deposit recipient that accepts crosschainDeposit calls
 */
contract MockDepositRecipient {
    bool public depositCalled;
    uint256 public lastAmount;
    address public lastDepositor;
    uint256 public lastPrecommitment;

    function crosschainDeposit(
        address depositor,
        uint256,
        uint256 precommitment
    ) external payable {
        depositCalled = true;
        lastAmount = msg.value;
        lastDepositor = depositor;
        lastPrecommitment = precommitment;
    }

    receive() external payable {}
}

/**
 * @notice Recipient that always fails
 */
contract FailingRecipient {
    function crosschainDeposit(address, uint256, uint256) external payable {
        revert("Always fails");
    }

    receive() external payable {
        revert("Always fails");
    }
}
