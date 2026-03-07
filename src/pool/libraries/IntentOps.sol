// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CrosschainWithdrawData} from "./Types.sol";
import {IShinobiPool} from "../interfaces/IShinobiPool.sol";
import {ShinobiIntent} from "../../oif/libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../../oif/libraries/ShinobiIntentLib.sol";
import {IShinobiInputSettler} from "../../oif/interfaces/IShinobiInputSettler.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {PoolStorageData, WithdrawalChainConfig} from "../storage/PoolStorage.sol";
import {PoolOps} from "./PoolOps.sol";

/// @title IntentOps - Shared intent creation logic for crosschain facets
library IntentOps {
    using ShinobiIntentLib for ShinobiIntent;

    error CombinedFeesTooHigh();

    struct IntentParams {
        bytes32 nullifierHash;
        bytes32 refundCommitment;
        uint256 escrowAmount;
        uint256 netAmount;
        uint256 refundFeeBPS;
        address feeRecipient;
        bytes4 refundSelector;
    }

    struct IntentResult {
        bytes32 orderId;
        uint256 netAmount;
        uint256 relayFee;
        uint256 solverFee;
    }

    function openIntent(
        PoolStorageData storage s,
        uint256 destChainId,
        CrosschainWithdrawData memory data,
        uint256 withdrawnValue,
        uint256 relayFeeBPS,
        uint256 refundFeeBPS,
        bytes32 nullifierHash,
        bytes32 refundCommitment,
        bytes4 refundSelector
    ) internal returns (IntentResult memory result) {
        result.relayFee = PoolOps.calculateFee(withdrawnValue, relayFeeBPS);
        result.solverFee = PoolOps.calculateFee(withdrawnValue, data.solverFeeBPS);
        uint256 escrowAmount = withdrawnValue - result.relayFee;
        result.netAmount = escrowAmount - result.solverFee;

        if (result.relayFee > 0) {
            PoolOps.transferETH(data.feeRecipient, result.relayFee);
        }

        IntentParams memory p = IntentParams({
            nullifierHash: nullifierHash,
            refundCommitment: refundCommitment,
            escrowAmount: escrowAmount,
            netAmount: result.netAmount,
            refundFeeBPS: refundFeeBPS,
            feeRecipient: data.feeRecipient,
            refundSelector: refundSelector
        });

        _openWithSettler(s, destChainId, data.encodedDestination, p);
        result.orderId = _computeOrderId(s, destChainId, data.encodedDestination, p);
    }

    function _openWithSettler(
        PoolStorageData storage s,
        uint256 destChainId,
        bytes32 encodedDestination,
        IntentParams memory p
    ) private {
        ShinobiIntent memory intent = _buildIntent(s, destChainId, encodedDestination, p);
        IShinobiInputSettler(s.withdrawalInputSettler).open{value: p.escrowAmount}(intent);
    }

    function _computeOrderId(
        PoolStorageData storage s,
        uint256 destChainId,
        bytes32 encodedDestination,
        IntentParams memory p
    ) private view returns (bytes32) {
        ShinobiIntent memory intent = _buildIntent(s, destChainId, encodedDestination, p);
        return intent.orderIdentifier();
    }

    function _buildIntent(
        PoolStorageData storage s,
        uint256 destChainId,
        bytes32 encodedDestination,
        IntentParams memory p
    ) private view returns (ShinobiIntent memory intent) {
        WithdrawalChainConfig storage dc = s.withdrawalChainConfig[destChainId];

        intent.user = address(this);
        intent.nonce = uint256(p.nullifierHash);
        intent.originChainId = block.chainid;
        intent.expires = uint32(block.timestamp) + dc.expiry;
        intent.fillDeadline = uint32(block.timestamp) + dc.fillDeadline;
        intent.fillOracle = dc.inputFillOracle;

        intent.inputs = new uint256[2][](1);
        intent.inputs[0] = [uint256(0), p.escrowAmount];

        intent.outputs = _buildOutputs(dc, destChainId, encodedDestination, p.netAmount);
        intent.refundCalldata = _encodeRefundCalldata(s.scope, p);
    }

    function _buildOutputs(
        WithdrawalChainConfig storage dc,
        uint256 destChainId,
        bytes32 encodedDestination,
        uint256 netAmount
    ) private view returns (MandateOutput[] memory outputs) {
        outputs = new MandateOutput[](1);
        MandateOutput memory o = outputs[0];
        o.oracle = bytes32(uint256(uint160(dc.outputFillOracle)));
        o.settler = bytes32(uint256(uint160(dc.withdrawalOutputSettler)));
        o.chainId = destChainId;
        o.amount = netAmount;
        o.recipient = bytes32(uint256(uint160(uint256(encodedDestination))));
    }

    function _encodeRefundCalldata(uint256 scope, IntentParams memory p)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            address(this),
            abi.encodeWithSelector(
                p.refundSelector,
                uint256(p.refundCommitment),
                p.feeRecipient,
                p.refundFeeBPS,
                scope
            )
        );
    }
}
