// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PoseidonT4} from "poseidon/PoseidonT4.sol";
import {Constants} from "../libraries/Constants.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "../FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title CrosschainDepositAction - Cross-chain deposit operations
contract CrosschainDepositAction is FacetBase, IFacet {
    event CrosschainDeposited(
        address indexed depositor, uint256 commitment, uint256 label, uint256 value, uint256 precommitmentHash
    );

    error MinimumDepositAmount();
    error PrecommitmentAlreadyUsed();
    error PrecommitmentOutOfField();
    error InvalidDepositValue();
    error OnlyDepositOutputSettler();
    error VettingFeeRecipientNotSet();
    error AssetConfigNotSet();

    /// @notice Cross-chain ETH deposit (called by DepositOutputSettler)
    function crosschainDeposit(address depositor, uint256 amount, uint256 precommitment)
        external
        payable
        nonReentrant
        whenAlive
        returns (uint256 commitment)
    {
        PoolStorageData storage s = PoolStorageLib.layout();

        if (msg.sender != s.depositOutputSettler) revert OnlyDepositOutputSettler();
        if (s.minimumDepositAmount == 0) revert AssetConfigNotSet();
        if (s.vettingFeeRecipient == address(0)) revert VettingFeeRecipientNotSet();
        if (msg.value != amount) revert PoolOps.InvalidWithdrawalAmount();
        if (amount < s.minimumDepositAmount) revert MinimumDepositAmount();
        if (amount >= type(uint128).max) revert InvalidDepositValue();
        if (precommitment >= Constants.SNARK_SCALAR_FIELD) revert PrecommitmentOutOfField();
        if (s.usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        s.usedPrecommitments[precommitment] = true;

        uint256 netAmount = PoolOps.deductFee(amount, s.vettingFeeBPS);
        uint256 vettingFee = amount - netAmount;

        uint256 label = uint256(keccak256(abi.encodePacked(s.scope, ++s.nonce))) % Constants.SNARK_SCALAR_FIELD;
        s.depositors[label] = depositor;

        commitment = PoseidonT4.hash([netAmount, label, precommitment]);
        PoolOps.insert(s, commitment);

        if (vettingFee > 0) {
            PoolOps.transferETH(s.vettingFeeRecipient, vettingFee);
        }

        emit CrosschainDeposited(depositor, commitment, label, netAmount, precommitment);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.crosschainDeposit.selector);
    }
}
