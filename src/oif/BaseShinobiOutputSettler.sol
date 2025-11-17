// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "./interfaces/IShinobiOutputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title BaseShinobiOutputSettler
 * @author Karandeep Singh
 * @notice Abstract base contract for Shinobi output settlers
 * @dev Provides common functionality for both deposit and withdrawal output settlers
 */
abstract contract BaseShinobiOutputSettler is IShinobiOutputSettler, ReentrancyGuard, Ownable {
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tracks which outputs have been filled
     * @dev Mapping: orderId => outputHash => fillRecordHash
     * @dev fillRecordHash = keccak256(solver, timestamp)
     * @dev Prevents double-filling and enables fill verification
     */
    mapping(bytes32 => mapping(bytes32 => bytes32)) internal _fillRecords;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when intent has no outputs or wrong number
    error InvalidOutput();

    /// @notice Thrown when output chain doesn't match current chain
    error InvalidChain();

    /// @notice Thrown when fill deadline has passed
    error FillDeadlinePassed();

    /// @notice Thrown when output has already been filled
    error AlreadyFilled();

    /// @notice Thrown when output token is not native ETH
    error InvalidAsset();

    /// @notice Thrown when ETH transfer fails
    error ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create and store fill record
     * @dev Creates fillRecordHash and stores it before external calls (CEI pattern)
     * @param orderId The unique order identifier
     * @param outputHash The hash of the output being filled
     * @param solver The solver providing liquidity
     */
    function _createAndStoreFillRecord(bytes32 orderId, bytes32 outputHash, address solver) internal {
        // Check if already filled
        bytes32 existingFillRecord = _fillRecords[orderId][outputHash];
        if (existingFillRecord != bytes32(0)) revert AlreadyFilled();

        // Create fill record: keccak256(solver, timestamp)
        bytes32 fillRecordHash =
            keccak256(abi.encodePacked(bytes32(uint256(uint160(solver))), uint32(block.timestamp)));

        // Store fill record BEFORE external call (CEI pattern)
        _fillRecords[orderId][outputHash] = fillRecordHash;
    }

    /**
     * @notice Validate output basic properties
     * @param output The output to validate
     */
    function _validateOutput(MandateOutput calldata output) internal view {
        // Validate output is for this chain
        if (output.chainId != block.chainid) revert InvalidChain();

        // Validate token is native ETH (only supported asset)
        if (output.token != bytes32(0)) revert InvalidAsset();
    }

    /**
     * @notice Transfer ETH to recipient
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function _transferETH(address recipient, uint256 amount) internal {
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get fill record for a specific output
     * @dev Returns fillRecordHash = keccak256(solver, timestamp) or bytes32(0) if not filled
     * @param orderId The order identifier
     * @param outputHash The output hash
     * @return payloadHash The fill record hash
     */
    function getFillRecord(bytes32 orderId, bytes32 outputHash)
        external
        view
        override
        returns (bytes32 payloadHash)
    {
        return _fillRecords[orderId][outputHash];
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH
     * @dev Required for solver to provide liquidity
     */
    receive() external payable {}
}
