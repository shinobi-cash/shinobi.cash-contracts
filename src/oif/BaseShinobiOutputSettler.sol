// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "./interfaces/IShinobiOutputSettler.sol";
import {IPayloadCreator} from "./interfaces/IPayloadCreator.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@oz/access/Ownable2Step.sol";
import {Pausable} from "@oz/utils/Pausable.sol";

/**
 * @title BaseShinobiOutputSettler
 * @author Karandeep Singh
 * @notice Abstract base contract for Shinobi output settlers
 * @dev Common functionality for deposit and withdrawal output settlers with IPayloadCreator support
 */
abstract contract BaseShinobiOutputSettler is IShinobiOutputSettler, IPayloadCreator, ReentrancyGuard, Ownable2Step, Pausable {
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => mapping(bytes32 => bytes32)) internal _fillRecords;
    mapping(bytes32 => bool) public validFillPayloads;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidOutput();
    error InvalidChain();
    error FillDeadlinePassed();
    error AlreadyFilled();
    error InvalidAsset();
    error ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createAndStoreFillRecord(
        bytes32 orderId,
        MandateOutput calldata output,
        address solver
    ) internal returns (bytes32 outputHash) {
        outputHash = output.getMandateOutputHash();
        if (_fillRecords[orderId][outputHash] != bytes32(0)) revert AlreadyFilled();

        bytes32 solverBytes = bytes32(uint256(uint160(solver)));
        uint32 timestamp = uint32(block.timestamp);

        bytes32 fillRecordHash = keccak256(abi.encodePacked(solverBytes, timestamp));
        _fillRecords[orderId][outputHash] = fillRecordHash;

        bytes memory fillPayload = MandateOutputEncodingLib.encodeFillDescriptionMemory(
            solverBytes,
            orderId,
            timestamp,
            output
        );
        validFillPayloads[keccak256(fillPayload)] = true;
    }

    function _validateOutput(MandateOutput calldata output) internal view {
        if (output.chainId != block.chainid) revert InvalidChain();
        if (output.token != bytes32(0)) revert InvalidAsset();
    }

    function _transferETH(address recipient, uint256 amount) internal {
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /// @inheritdoc IPayloadCreator
    function arePayloadsValid(bytes[] calldata payloads) external view override returns (bool valid) {
        for (uint256 i = 0; i < payloads.length; i++) {
            if (!validFillPayloads[keccak256(payloads[i])]) return false;
        }
        return true;
    }

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
                          EMERGENCY PAUSE
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /*//////////////////////////////////////////////////////////////
                          ADMIN ETH RECOVERY
    //////////////////////////////////////////////////////////////*/

    error WithdrawFailed();

    function withdrawETH(address payable recipient, uint256 amount) external onlyOwner {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert WithdrawFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
