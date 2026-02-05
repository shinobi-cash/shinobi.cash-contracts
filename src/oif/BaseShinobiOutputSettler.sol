// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "./interfaces/IShinobiOutputSettler.sol";
import {IPayloadCreator} from "./interfaces/IPayloadCreator.sol";
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
 * @dev Implements IPayloadCreator for Hyperlane fill proof validation
 */
abstract contract BaseShinobiOutputSettler is IShinobiOutputSettler, IPayloadCreator, ReentrancyGuard, Ownable {
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

    /**
     * @notice Tracks valid fill payload hashes for IPayloadCreator validation
     * @dev Mapping: payloadHash => true if valid
     * @dev Set when a fill is recorded, checked by HyperlaneOracle.submit()
     */
    mapping(bytes32 => bool) public validFillPayloads;

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
     * @dev Also stores fill payload hash for IPayloadCreator/Hyperlane validation
     * @param orderId The unique order identifier
     * @param output The full output being filled (needed for fill payload encoding)
     * @param solver The solver providing liquidity
     * @return outputHash The hash of the output (for event emission)
     */
    function _createAndStoreFillRecord(
        bytes32 orderId,
        MandateOutput calldata output,
        address solver
    ) internal returns (bytes32 outputHash) {
        // Compute output hash for fill tracking
        outputHash = output.getMandateOutputHash();

        // Check if already filled
        bytes32 existingFillRecord = _fillRecords[orderId][outputHash];
        if (existingFillRecord != bytes32(0)) revert AlreadyFilled();

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        uint32 timestamp = uint32(block.timestamp);

        // Create fill record: keccak256(solver, timestamp)
        bytes32 fillRecordHash = keccak256(abi.encodePacked(solverBytes, timestamp));

        // Store fill record BEFORE external call (CEI pattern)
        _fillRecords[orderId][outputHash] = fillRecordHash;

        // Compute and store fill payload hash for IPayloadCreator validation
        // This allows HyperlaneOracle.submit() to verify the fill is legitimate
        bytes memory fillPayload = MandateOutputEncodingLib.encodeFillDescriptionMemory(
            solverBytes,
            orderId,
            timestamp,
            output
        );
        validFillPayloads[keccak256(fillPayload)] = true;
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
                    IPAYLOADCREATOR IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate that fill payloads were created by this contract
     * @dev Called by HyperlaneOracle before relaying fill proofs to origin chain
     * @param payloads Array of encoded fill descriptions to validate
     * @return valid True if all payloads are valid fill records
     */
    function arePayloadsValid(bytes[] calldata payloads) external view override returns (bool valid) {
        for (uint256 i = 0; i < payloads.length; i++) {
            if (!validFillPayloads[keccak256(payloads[i])]) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Encode a fill description for Hyperlane submission
     * @dev Helper for solvers to create the correct payload format
     * @param solver The solver who filled the output
     * @param orderId The order identifier
     * @param timestamp The fill timestamp
     * @param output The output that was filled
     * @return payload The encoded fill description
     */
    function encodeFillPayload(
        address solver,
        bytes32 orderId,
        uint32 timestamp,
        MandateOutput calldata output
    ) external pure returns (bytes memory payload) {
        return MandateOutputEncodingLib.encodeFillDescription(
            bytes32(uint256(uint160(solver))),
            orderId,
            timestamp,
            output
        );
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
