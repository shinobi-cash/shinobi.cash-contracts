// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {Constants} from "contracts/lib/Constants.sol";
import {ShinobiCashPool} from "../ShinobiCashPool.sol";
import {ICrosschainWithdrawalProofVerifier} from "../interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../interfaces/ICrosschainWithdraw2Verifier.sol";

/**
 * @title ShinobiCashPoolSimple
 * @author Karandeep Singh
 * @notice Native ETH implementation of ShinobiCashPool
 */
contract ShinobiCashPoolSimple is ShinobiCashPool {

    error InsufficientValue();
    error FailedToSendNativeAsset();

    constructor(
        address _entrypoint,
        address _withdrawalVerifier,
        address _ragequitVerifier,
        ICrosschainWithdrawalProofVerifier _crossChainVerifier,
        IWithdraw2Verifier _withdraw2Verifier,
        ICrosschainWithdraw2Verifier _crossChainWithdraw2Verifier
    ) ShinobiCashPool(
        _entrypoint,
        _withdrawalVerifier,
        _ragequitVerifier,
        Constants.NATIVE_ASSET,
        _crossChainVerifier,
        _withdraw2Verifier,
        _crossChainWithdraw2Verifier
    ) {}

    function _pull(address, uint256 _amount) internal override {
        if (msg.value != _amount) revert InsufficientValue();
    }

    function _push(address _recipient, uint256 _amount) internal override {
        (bool success,) = _recipient.call{value: _amount}("");
        if (!success) revert FailedToSendNativeAsset();
    }
}
