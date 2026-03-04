// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoseidonT4} from "poseidon/PoseidonT4.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IFacet} from "../interfaces/IFacet.sol";
import {FacetBase} from "./FacetBase.sol";
import {PoolStorageData, PoolStorageLib} from "../storage/PoolStorage.sol";
import {PoolOps} from "../libraries/PoolOps.sol";

/// @title DepositFacet - Same-chain and cross-chain deposit operations
contract DepositFacet is FacetBase, IFacet {
    using SafeERC20 for IERC20;

    event Deposited(
        address indexed depositor, uint256 commitment, uint256 label, uint256 value, uint256 precommitmentHash
    );
    event CrosschainDeposited(
        address indexed depositor, address indexed pool, uint256 precommitment, uint256 commitment, uint256 amount
    );

    error MinimumDepositAmount();
    error PrecommitmentAlreadyUsed();
    error InvalidDepositValue();
    error OnlyDepositOutputSettler();
    error InvalidAsset();

    /// @notice Same-chain native ETH deposit
    function deposit(uint256 precommitment) external payable nonReentrant whenAlive returns (uint256 commitment) {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (msg.value < s.minimumDepositAmount) revert MinimumDepositAmount();
        if (msg.value >= type(uint128).max) revert InvalidDepositValue();
        if (s.usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        s.usedPrecommitments[precommitment] = true;

        uint256 netAmount = PoolOps.deductFee(msg.value, s.vettingFeeBPS);

        uint256 label = uint256(keccak256(abi.encodePacked(s.scope, ++s.nonce))) % Constants.SNARK_SCALAR_FIELD;
        s.depositors[label] = msg.sender;

        commitment = PoseidonT4.hash([netAmount, label, precommitment]);
        PoolOps.insert(s, commitment);

        emit Deposited(msg.sender, commitment, label, netAmount, precommitment);
    }

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
        if (msg.value != amount) revert PoolOps.InvalidWithdrawalAmount();
        if (amount < s.minimumDepositAmount) revert MinimumDepositAmount();
        if (amount >= type(uint128).max) revert InvalidDepositValue();
        if (s.usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        s.usedPrecommitments[precommitment] = true;

        uint256 netAmount = PoolOps.deductFee(amount, s.vettingFeeBPS);

        uint256 label = uint256(keccak256(abi.encodePacked(s.scope, ++s.nonce))) % Constants.SNARK_SCALAR_FIELD;
        s.depositors[label] = depositor;

        commitment = PoseidonT4.hash([netAmount, label, precommitment]);
        PoolOps.insert(s, commitment);

        emit CrosschainDeposited(depositor, address(this), precommitment, commitment, netAmount);
    }

    /// @notice Cross-chain ERC20 deposit (called by DepositOutputSettler)
    function crosschainDepositERC20(IERC20 asset, address depositor, uint256 amount, uint256 precommitment)
        external
        nonReentrant
        whenAlive
        returns (uint256 commitment)
    {
        PoolStorageData storage s = PoolStorageLib.layout();
        if (msg.sender != s.depositOutputSettler) revert OnlyDepositOutputSettler();
        if (address(asset) == Constants.NATIVE_ASSET) revert InvalidAsset();
        if (amount < s.minimumDepositAmount) revert MinimumDepositAmount();
        if (amount >= type(uint128).max) revert InvalidDepositValue();
        if (s.usedPrecommitments[precommitment]) revert PrecommitmentAlreadyUsed();
        s.usedPrecommitments[precommitment] = true;

        asset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 netAmount = PoolOps.deductFee(amount, s.vettingFeeBPS);

        uint256 label = uint256(keccak256(abi.encodePacked(s.scope, ++s.nonce))) % Constants.SNARK_SCALAR_FIELD;
        s.depositors[label] = depositor;

        commitment = PoseidonT4.hash([netAmount, label, precommitment]);
        PoolOps.insert(s, commitment);

        emit CrosschainDeposited(depositor, address(this), precommitment, commitment, netAmount);
    }

    // ── ERC-8153 ──

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(
            this.deposit.selector, this.crosschainDeposit.selector, this.crosschainDepositERC20.selector
        );
    }
}
