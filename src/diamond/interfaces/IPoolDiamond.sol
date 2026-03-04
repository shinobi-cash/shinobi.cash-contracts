// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {CrosschainProofLib} from "../../core/libraries/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "../../core/libraries/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "../../core/libraries/CrosschainWithdraw2ProofLib.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {AssociationSetData} from "../storage/PoolStorage.sol";

/// @title IPoolDiamond - Combined interface for the pool diamond
/// @notice Used by paymasters and external callers to interact with the diamond
interface IPoolDiamond {
    // ── Structs ──

    struct ReplaceAction {
        address oldFacet;
        address newFacet;
    }

    // ── Events (Pool) ──

    event Deposited(
        address indexed depositor, uint256 commitment, uint256 label, uint256 value, uint256 precommitmentHash
    );
    event CrosschainDeposited(
        address indexed depositor, address indexed pool, uint256 precommitment, uint256 commitment, uint256 amount
    );
    event Withdrawn(address indexed processooor, uint256 value, uint256 spentNullifier, uint256 newCommitment);
    event WithdrawalRelayed(
        address indexed relayer, address indexed recipient, address indexed asset, uint256 amount, uint256 feeAmount
    );
    event Ragequit(address indexed ragequitter, uint256 commitment, uint256 label, uint256 value);
    event LeafInserted(uint256 _index, uint256 _leaf, uint256 _root);
    event PoolDied();

    // ── Events (Cross-chain) ──

    event CrosschainWithdrawalIntentRelayed(
        address indexed relayer,
        bytes32 indexed crosschainRecipient,
        address indexed asset,
        uint256 amount,
        uint256 relayFee,
        uint256 solverFee,
        bytes32 orderId
    );
    event Refunded(uint256 amount, uint256 indexed refundCommitmentHash, uint256 refundFee, address indexed feeRecipient);
    event RefundCommitmentInserted(uint256 indexed refundCommitmentHash, uint256 amount);

    // ── Events (Admin) ──

    event RootUpdated(uint256 root, string ipfsCID, uint256 timestamp);
    event AssetConfigUpdated(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS);
    event WithdrawalInputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event DepositOutputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event MaxSolverFeeBPSUpdated(uint256 oldValue, uint256 newValue);
    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    );
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    // ── Events (Diamond) ──

    event FacetAdded(address indexed facet);
    event FacetReplaced(address indexed oldFacet, address indexed newFacet);
    event FacetRemoved(address indexed facet);

    // ── Deposit ──

    function deposit(uint256 precommitment) external payable returns (uint256 commitment);

    function crosschainDeposit(address depositor, uint256 amount, uint256 precommitment)
        external
        payable
        returns (uint256 commitment);

    function crosschainDepositERC20(IERC20 asset, address depositor, uint256 amount, uint256 precommitment)
        external
        returns (uint256 commitment);

    // ── Withdraw ──

    function withdraw(IPrivacyPool.Withdrawal calldata withdrawal, ProofLib.WithdrawProof calldata proof) external;

    function crosschainWithdraw(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof calldata proof
    ) external;

    function withdraw2(IPrivacyPool.Withdrawal calldata withdrawal, Withdraw2ProofLib.Withdraw2Proof calldata proof)
        external;

    function crosschainWithdraw2(
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof
    ) external;

    // ── Ragequit ──

    function ragequit(ProofLib.RagequitProof calldata proof) external;

    // ── Refund ──

    function handleRefund(uint256 refundCommitmentHash, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable;

    // ── Admin ──

    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function transferAdmin(address newAdmin) external;
    function acceptAdmin() external;
    function setAssetConfig(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS) external;
    function setMaxSolverFeeBPS(uint256 maxSolverFeeBPS) external;
    function setWithdrawalInputSettler(address settler) external;
    function setDepositOutputSettler(address settler) external;
    function setWithdrawalChainConfig(
        uint256 chainId,
        address outputSettler,
        address outputOracle,
        address fillOracle,
        uint32 fillDeadline,
        uint32 expiry
    ) external;
    function updateRoot(uint256 root, string calldata ipfsCID) external returns (uint256 index);
    function windDown() external;
    function withdrawFees(address recipient) external;
    function upgradeDiamond(
        address[] calldata addFacets,
        address[] calldata removeFacets,
        ReplaceAction[] calldata replaceFacets
    ) external;

    // ── Views ──

    function ASSET() external view returns (address);
    function SCOPE() external view returns (uint256);
    function nonce() external view returns (uint256);
    function dead() external view returns (bool);
    function roots(uint256 index) external view returns (uint256);
    function currentRootIndex() external view returns (uint32);
    function currentRoot() external view returns (uint256);
    function currentTreeDepth() external view returns (uint256);
    function currentTreeSize() external view returns (uint256);
    function nullifierHashes(uint256 hash) external view returns (bool);
    function depositors(uint256 label) external view returns (address);
    function usedPrecommitments(uint256 precommitment) external view returns (bool);
    function ROOT_HISTORY_SIZE() external pure returns (uint32);
    function MAX_TREE_DEPTH() external pure returns (uint32);
    function latestRoot() external view returns (uint256);
    function rootByIndex(uint256 index) external view returns (uint256);
    function associationSets(uint256 index) external view returns (uint256 root, string memory ipfsCID, uint256 timestamp);
    function assetConfig() external view returns (uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS);
    function maxSolverFeeBPS() external view returns (uint256);
    function accumulatedFees() external view returns (uint256);
    function withdrawalInputSettler() external view returns (address);
    function depositOutputSettler() external view returns (address);
    function withdrawalChainConfig(uint256 chainId)
        external
        view
        returns (bool isConfigured, uint32 fillDeadline, uint32 expiry, address withdrawalOutputSettler, address withdrawalFillOracle, address fillOracle);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function pendingAdmin() external view returns (address);

    // ── Loupe (ERC-8153) ──

    function facetAddress(bytes4 selector) external view returns (address);
    function facetAddresses() external view returns (address[] memory);
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory);
}
