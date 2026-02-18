// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {BaseShinobiOutputSettler} from "./BaseShinobiOutputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title ShinobiDepositOutputSettler
 * @author Karandeep Singh
 * @notice Output settler for cross-chain deposits on destination chain (pool chain)
 * @dev Validates intent proof via intentOracle before filling deposit intents
 */
contract ShinobiDepositOutputSettler is BaseShinobiOutputSettler {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable intentOracle;

    struct OriginChainConfig {
        address hyperlaneOracle;
        address depositEntrypoint;
        bool isConfigured;
    }

    mapping(uint256 => OriginChainConfig) public originChainConfigs;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event OriginChainConfigSet(
        uint256 indexed chainId,
        address indexed hyperlaneOracle,
        address indexed depositEntrypoint
    );
    event OriginChainConfigRemoved(uint256 indexed chainId);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidIntentOracle();
    error IntentOracleMismatch();
    error IntentNotProven();
    error EmptyCallbackData();
    error CallbackFailed();
    error OriginChainNotConfigured(uint256 chainId);
    error InvalidAddress();
    error InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _intentOracle) BaseShinobiOutputSettler(_owner) {
        if (_intentOracle == address(0)) revert InvalidIntentOracle();
        intentOracle = _intentOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setOriginChainConfig(
        uint256 _chainId,
        address _hyperlaneOracle,
        address _depositEntrypoint
    ) external onlyOwner {
        if (_chainId == 0) revert InvalidChainId();
        if (_hyperlaneOracle == address(0)) revert InvalidAddress();
        if (_depositEntrypoint == address(0)) revert InvalidAddress();

        originChainConfigs[_chainId] = OriginChainConfig({
            hyperlaneOracle: _hyperlaneOracle,
            depositEntrypoint: _depositEntrypoint,
            isConfigured: true
        });

        emit OriginChainConfigSet(_chainId, _hyperlaneOracle, _depositEntrypoint);
    }

    function removeOriginChainConfig(uint256 _chainId) external onlyOwner {
        delete originChainConfigs[_chainId];
        emit OriginChainConfigRemoved(_chainId);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a deposit intent on pool chain (destination)
     * @dev Validates intent proof via configured intentOracle before filling
     */
    function fill(ShinobiIntent calldata intent) external payable override nonReentrant {
        if (intent.outputs.length != 1) revert InvalidOutput();
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();
        if (intent.intentOracle != intentOracle) revert IntentOracleMismatch();

        OriginChainConfig memory originConfig = originChainConfigs[intent.originChainId];
        if (!originConfig.isConfigured) revert OriginChainNotConfigured(intent.originChainId);

        bytes32 orderId = intent.orderIdentifier();

        if (
            !IInputOracle(intentOracle).isProven(
                intent.originChainId,
                bytes32(uint256(uint160(originConfig.hyperlaneOracle))),
                bytes32(uint256(uint160(originConfig.depositEntrypoint))),
                keccak256(abi.encode(orderId))
            )
        ) {
            revert IntentNotProven();
        }

        _fillOutput(orderId, intent.outputs[0], msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _fillOutput(bytes32 orderId, MandateOutput calldata output, address solver) internal {
        _validateOutput(output);
        _createAndStoreFillRecord(orderId, output, solver);

        address recipient = address(uint160(uint256(output.recipient)));
        uint256 amount = output.amount;

        if (output.call.length == 0) revert EmptyCallbackData();

        (bool success,) = recipient.call{value: amount}(output.call);
        if (!success) revert CallbackFailed();

        emit OutputFilled(
            orderId, bytes32(uint256(uint160(solver))), uint32(block.timestamp), output, amount
        );
    }
}
