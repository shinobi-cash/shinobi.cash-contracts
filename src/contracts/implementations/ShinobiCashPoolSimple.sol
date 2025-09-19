// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {Constants} from "contracts/lib/Constants.sol";
import {ShinobiCashPool} from "../ShinobiCashPool.sol";
import {ICrossChainWithdrawalProofVerifier} from "../interfaces/ICrossChainWithdrawalProofVerifier.sol";

/**
 * @title ShinobiCashPoolSimple
 * @notice Native asset implementation of Shinobi Cash Pool with cross-chain capabilities
 * @dev Extends ShinobiCashPool for native ETH with cross-chain withdrawal support
 */
contract ShinobiCashPoolSimple is ShinobiCashPool {
    
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when insufficient value is sent
    error InsufficientValue();

    /// @notice Thrown when failed to send native asset
    error FailedToSendNativeAsset();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the Shinobi Cash Pool for native assets
     * @param _entrypoint The entrypoint contract address
     * @param _withdrawalVerifier The standard withdrawal proof verifier (8 signals)
     * @param _ragequitVerifier The ragequit proof verifier
     * @param _crossChainVerifier The cross-chain withdrawal proof verifier (9 signals)
     */
    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        ICrossChainWithdrawalProofVerifier _crossChainVerifier
    ) ShinobiCashPool(
        _entrypoint,
        _withdrawalVerifier,
        _ragequitVerifier,
        Constants.NATIVE_ASSET,
        _crossChainVerifier
    ) {}

    /*//////////////////////////////////////////////////////////////
                        ASSET TRANSFER IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle receiving native asset
     * @param _amount The amount of asset receiving
     */
    function _pull(address, uint256 _amount) internal override {
        if (msg.value != _amount) revert InsufficientValue();
    }

    /**
     * @notice Handle sending native asset
     * @param _recipient The address of the user receiving the asset
     * @param _amount The amount of native asset being sent
     */
    function _push(address _recipient, uint256 _amount) internal override {
        (bool success,) = _recipient.call{value: _amount}('');
        if (!success) revert FailedToSendNativeAsset();
    }
}