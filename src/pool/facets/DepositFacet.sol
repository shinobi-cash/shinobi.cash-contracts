// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoseidonT4} from "poseidon/PoseidonT4.sol";
import {Constants} from "../libraries/Constants.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title DepositFacet - Same-chain deposit operations
contract DepositFacet is FacetBase, IFacet {
    event Deposited(
        address indexed depositor, uint256 commitment, uint256 label, uint256 value, uint256 precommitmentHash
    );

    error MinimumDepositAmount();
    error PrecommitmentAlreadyUsed();
    error InvalidDepositValue();
    error VettingFeeRecipientNotSet();
    error AssetConfigNotSet();

    /// @notice Same-chain native ETH deposit
    function deposit(uint256 precommitment) external payable nonReentrant whenAlive returns (uint256 commitment) {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (s.minimumDepositAmount == 0) revert AssetConfigNotSet();
        if (s.vettingFeeRecipient == address(0)) revert VettingFeeRecipientNotSet();
        if (msg.value < s.minimumDepositAmount) revert MinimumDepositAmount();
        if (msg.value >= type(uint128).max) revert InvalidDepositValue();
        if (s.usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        s.usedPrecommitments[precommitment] = true;

        uint256 netAmount = PoolOps.deductFee(msg.value, s.vettingFeeBPS);
        uint256 vettingFee = msg.value - netAmount;

        uint256 label = uint256(keccak256(abi.encodePacked(s.scope, ++s.nonce))) % Constants.SNARK_SCALAR_FIELD;
        s.depositors[label] = msg.sender;

        commitment = PoseidonT4.hash([netAmount, label, precommitment]);
        PoolOps.insert(s, commitment);

        if (vettingFee > 0) {
            PoolOps.transferETH(s.vettingFeeRecipient, vettingFee);
        }

        emit Deposited(msg.sender, commitment, label, netAmount, precommitment);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.deposit.selector);
    }
}
