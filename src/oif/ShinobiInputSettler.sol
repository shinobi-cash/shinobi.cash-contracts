// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "./interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {Ownable2Step, Ownable} from "@oz/access/Ownable2Step.sol";
import {Pausable} from "@oz/utils/Pausable.sol";

/**
 * @title ShinobiInputSettler
 * @author Karandeep Singh
 * @notice Input settler for Shinobi Cash cross-chain intents following OIF standard
 * @dev Handles origin-side intent escrow, fill validation, and refunds
 */
contract ShinobiInputSettler is IShinobiInputSettler, Ownable2Step, Pausable {
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable entrypoint;

    mapping(bytes32 => OrderStatus) public override orderStatus;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidEntrypoint();
    error UnauthorizedCaller();
    error InvalidOrderStatus();
    error InvalidChain();
    error InvalidAmount();
    error InvalidAsset();
    error InvalidIntent();
    error DeadlinePassed();
    error ExpiryNotReached();
    error InvalidDeadlineOrder();
    error ReentrancyDetected();
    error NotOrderOwner();
    error InvalidSolveParamsLength();
    error MultipleSolversNotSupported();
    error FilledTooLate(uint32 deadline, uint32 filledAt);
    error ETHTransferFailed();
    error InvalidRefundCalldataLength();
    error InvalidRefundTarget();
    error DirtyUpperBits();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _entrypoint, address _owner) Ownable(_owner) {
        if (_entrypoint == address(0)) revert InvalidEntrypoint();
        entrypoint = _entrypoint;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new intent and escrow funds on origin chain
     * @dev Only the configured entrypoint can call this function
     */
    function open(ShinobiIntent calldata intent) external payable override {
        if (msg.sender != entrypoint) revert UnauthorizedCaller();

        _validateIntent(intent);
        bytes32 orderId = orderIdentifier(intent);
        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();

        orderStatus[orderId] = OrderStatus.Deposited;
        _collectInputs(intent.inputs);
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        emit Open(orderId, intent);
    }

    /**
     * @notice Finalize intent after solver fills outputs on destination chain
     * @dev Can only be called by the solver who filled the outputs (verified via oracle)
     */
    function finalise(
        ShinobiIntent calldata intent,
        IShinobiInputSettler.SolveParams[] calldata solveParams,
        bytes32 destination
    ) external whenNotPaused {
        bytes32 orderId = orderIdentifier(intent);
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();
        if (block.timestamp > intent.fillDeadline) revert DeadlinePassed();

        bytes32 solver = solveParams[0].solver;
        for (uint256 i = 1; i < solveParams.length; i++) {
            if (solveParams[i].solver != solver) revert MultipleSolversNotSupported();
        }

        _orderOwnerIsCaller(solver);
        _validateFills(intent, orderId, solveParams);

        orderStatus[orderId] = OrderStatus.Claimed;
        uint256 amount = _calculateTotalAmount(intent.inputs);

        address destinationAddress = _bytes32ToAddress(destination);
        (bool success,) = destinationAddress.call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Finalised(orderId, solver, destination);
    }

    /**
     * @notice Refund an expired intent back to the original user
     * @dev Can be called by anyone after intent expires. Funds always sent to intent.user.
     */
    function refund(ShinobiIntent calldata intent) external override {
        bytes32 orderId = orderIdentifier(intent);
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();
        if (block.timestamp <= intent.expires) revert ExpiryNotReached();

        orderStatus[orderId] = OrderStatus.Refunded;
        uint256 totalAmount = _calculateTotalAmount(intent.inputs);

        if (intent.refundCalldata.length == 0) {
            (bool success,) = intent.user.call{value: totalAmount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            if (intent.refundCalldata.length < 64) revert InvalidRefundCalldataLength();

            (address target, bytes memory functionCalldata) =
                abi.decode(intent.refundCalldata, (address, bytes));

            if (target != entrypoint) revert InvalidRefundTarget();

            (bool success,) = target.call{value: totalAmount}(functionCalldata);
            if (!success) revert ETHTransferFailed();
        }

        emit Refunded(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                          EMERGENCY PAUSE
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateIntent(ShinobiIntent calldata intent) internal view {
        if (intent.originChainId != block.chainid) revert InvalidChain();
        if (block.timestamp >= intent.fillDeadline) revert DeadlinePassed();
        if (block.timestamp >= intent.expires) revert DeadlinePassed();
        if (intent.expires <= intent.fillDeadline) revert InvalidDeadlineOrder();
        if (intent.inputs.length == 0) revert InvalidIntent();
        if (intent.outputs.length == 0) revert InvalidIntent();
    }

    function _collectInputs(uint256[2][] calldata inputs) internal {
        if (inputs.length == 0) revert InvalidAmount();

        uint256 expectedEthValue = 0;
        for (uint256 i = 0; i < inputs.length; i++) {
            if (inputs[i][0] != 0) revert InvalidAsset();
            expectedEthValue += inputs[i][1];
        }

        if (msg.value != expectedEthValue) revert InvalidAmount();
    }

    function _validateFills(
        ShinobiIntent calldata intent,
        bytes32 orderId,
        IShinobiInputSettler.SolveParams[] calldata solveParams
    ) internal view {
        uint256 numOutputs = intent.outputs.length;
        if (solveParams.length != numOutputs) revert InvalidSolveParamsLength();

        bytes memory proofSeries = new bytes(128 * numOutputs);

        for (uint256 i = 0; i < numOutputs; i++) {
            uint32 outputFilledAt = solveParams[i].timestamp;
            if (intent.fillDeadline < outputFilledAt) {
                revert FilledTooLate(intent.fillDeadline, outputFilledAt);
            }

            MandateOutput memory output = MandateOutput({
                chainId: intent.outputs[i].chainId,
                oracle: intent.outputs[i].oracle,
                settler: intent.outputs[i].settler,
                token: intent.outputs[i].token,
                amount: intent.outputs[i].amount,
                recipient: intent.outputs[i].recipient,
                call: intent.outputs[i].call,
                context: intent.outputs[i].context
            });

            bytes32 payloadHash = keccak256(
                MandateOutputEncodingLib.encodeFillDescriptionMemory(
                    solveParams[i].solver, orderId, outputFilledAt, output
                )
            );

            bytes32 remoteChainId = bytes32(output.chainId);
            bytes32 remoteOracle = output.oracle;
            bytes32 remoteSettler = output.settler;

            assembly {
                let offset := add(proofSeries, add(32, mul(i, 128)))
                mstore(offset, remoteChainId)
                mstore(add(offset, 32), remoteOracle)
                mstore(add(offset, 64), remoteSettler)
                mstore(add(offset, 96), payloadHash)
            }
        }

        IInputOracle(intent.fillOracle).efficientRequireProven(proofSeries);
    }

    function _orderOwnerIsCaller(bytes32 orderOwner) internal view {
        if (_bytes32ToAddress(orderOwner) != msg.sender) revert NotOrderOwner();
    }

    function _calculateTotalAmount(uint256[2][] calldata inputs)
        internal
        pure
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < inputs.length; i++) {
            totalAmount += inputs[i][1];
        }
    }

    function _bytes32ToAddress(bytes32 b) internal pure returns (address addr) {
        if (uint256(b) > type(uint160).max) revert DirtyUpperBits();
        assembly { addr := b }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function orderIdentifier(ShinobiIntent memory intent) public pure override returns (bytes32) {
        return intent.orderIdentifier();
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
