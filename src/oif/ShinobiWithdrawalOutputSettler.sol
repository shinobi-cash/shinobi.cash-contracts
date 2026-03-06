// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {BaseShinobiOutputSettler} from "./BaseShinobiOutputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title ShinobiWithdrawalOutputSettler
 * @author Karandeep Singh
 * @notice Output settler for cross-chain withdrawals on destination chain (user's chain)
 * @dev Optimistic settlement - no intent proof validation (ZK proof already validated on origin)
 */
contract ShinobiWithdrawalOutputSettler is BaseShinobiOutputSettler {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable fillOracle;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidFillOracle();
    error FillOracleMismatch();
    error InsufficientFillValue();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _fillOracle) BaseShinobiOutputSettler(_owner) {
        if (_fillOracle == address(0)) revert InvalidFillOracle();
        fillOracle = _fillOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a withdrawal intent on user's chain (destination)
     * @dev Optimistic settlement - no intent proof validation (ZK proof validated on origin)
     */
    function fill(ShinobiIntent calldata intent) external payable override nonReentrant {
        if (intent.outputs.length != 1) revert InvalidOutput();
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();
        if (intent.fillOracle != fillOracle) revert FillOracleMismatch();

        bytes32 orderId = intent.orderIdentifier();
        _fillOutput(orderId, intent.outputs[0], msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _fillOutput(bytes32 orderId, MandateOutput calldata output, address solver) internal {
        _validateOutput(output);
        if (msg.value < output.amount) revert InsufficientFillValue();
        _createAndStoreFillRecord(orderId, output, solver);

        address recipient = address(uint160(uint256(output.recipient)));
        uint256 amount = output.amount;

        _transferETH(recipient, amount);

        emit OutputFilled(
            orderId, bytes32(uint256(uint160(solver))), uint32(block.timestamp), output, amount
        );
    }
}
