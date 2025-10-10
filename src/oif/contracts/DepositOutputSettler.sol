// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "../interfaces/IShinobiOutputSettler.sol";
import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../lib/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title DepositOutputSettler
 * @notice Handles cross-chain deposit fills on destination chain (pool chain - Ethereum)
 * @dev CRITICAL SECURITY: Validates intent proof to prevent depositor address spoofing
 * @dev Solver provides ETH and calls pool.deposit() with VERIFIED depositor address
 */
contract DepositOutputSettler is IShinobiOutputSettler {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping: orderId => outputHash => fillRecordHash
    /// @dev fillRecordHash = keccak256(solver, timestamp)
    mapping(bytes32 => mapping(bytes32 => bytes32)) internal _fillRecords;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidChain();
    error FillDeadlinePassed();
    error IntentNotProven();
    error AlreadyFilled();
    error InvalidOutput();
    error CallbackFailed();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a deposit intent on destination chain (pool chain)
     * @dev CRITICAL: Validates intent proof before calling pool.deposit()
     * @dev This prevents solver from spoofing depositor address
     * @param intent The deposit intent from origin chain
     */
    function fill(ShinobiIntent calldata intent) external payable override {
        // Validate this is the correct destination chain
        if (intent.outputs.length == 0) revert InvalidOutput();
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

        // Validate fill deadline
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

        // CRITICAL SECURITY CHECK: Validate intent proof
        // This proves that intent.user = msg.sender on origin chain
        // Without this, solver could spoof any depositor address
        bytes32 orderId = intent.orderIdentifier();
        if (!IInputOracle(intent.intentOracle).isProven(
            intent.originChainId,
            bytes32(uint256(uint160(intent.intentOracle))),
            bytes32(uint256(uint160(address(this)))),
            orderId
        )) {
            revert IntentNotProven();
        }

        // Fill each output (typically just one for deposits)
        for (uint256 i = 0; i < intent.outputs.length; i++) {
            _fillOutput(orderId, intent.outputs[i], msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _fillOutput(
        bytes32 orderId,
        MandateOutput calldata output,
        address solver
    ) internal {
        // Validate output is for this chain
        if (output.chainId != block.chainid) revert InvalidChain();

        // Get output hash
        bytes32 outputHash = output.getMandateOutputHash();

        // Check if already filled
        bytes32 existingFillRecord = _fillRecords[orderId][outputHash];
        if (existingFillRecord != bytes32(0)) revert AlreadyFilled();

        // Create fill record
        bytes32 fillRecordHash = keccak256(abi.encodePacked(
            bytes32(uint256(uint160(solver))),
            uint32(block.timestamp)
        ));

        // Store fill record
        _fillRecords[orderId][outputHash] = fillRecordHash;

        // Get recipient (entrypoint) and amount
        address recipient = address(uint160(uint256(output.recipient)));
        uint256 amount = output.amount;

        // Validate token is native ETH
        if (output.token != bytes32(0)) revert InvalidOutput();

        // Execute callback with ETH payment (should be ShinobiCashEntrypoint.crossChainDeposit)
        // The callback contains the VERIFIED depositor address from intent.user
        if (output.call.length == 0) revert InvalidOutput();

        (bool success, ) = recipient.call{value: amount}(output.call);
        if (!success) revert CallbackFailed();

        emit OutputFilled(
            orderId,
            bytes32(uint256(uint160(solver))),
            uint32(block.timestamp),
            output,
            amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getFillRecord(
        bytes32 orderId,
        bytes32 outputHash
    ) external view override returns (bytes32 payloadHash) {
        return _fillRecords[orderId][outputHash];
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
