// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WithdrawData, CrosschainWithdrawData} from "../libraries/Types.sol";
import {WithdrawProofLib} from "../../proofLibs/WithdrawProofLib.sol";
import {RagequitProofLib} from "../../proofLibs/RagequitProofLib.sol";
import {CrosschainProofLib} from "../../proofLibs/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "../../proofLibs/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "../../proofLibs/CrosschainWithdraw2ProofLib.sol";
import {AssociationSetData} from "../storage/PoolStorage.sol";

/// @title IShinobiPool - Combined interface for the Shinobi pool
/// @notice Used by paymasters and external callers to interact with the pool
interface IShinobiPool {
    // ── Structs ──

    struct ReplaceAction {
        address oldFacet;
        address newFacet;
    }

    // ── Events (Diamond built-in) ──

    event RootUpdated(uint256 root, string ipfsCID, uint256 timestamp);
    event AssetConfigUpdated(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS);
    event WithdrawalInputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event DepositOutputSettlerUpdated(address indexed oldSettler, address indexed newSettler);
    event MaxSolverFeeBPSUpdated(uint256 oldValue, uint256 newValue);
    event MaxRefundFeeBPSUpdated(uint256 oldValue, uint256 newValue);
    event WithdrawalChainConfigured(
        uint256 indexed chainId,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address outputFillOracle,
        address inputFillOracle
    );
    event VettingFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event AdminTransferStarted(address indexed currentAdmin, address indexed newAdmin);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    // ── Events (Diamond) ──

    event FacetAdded(address indexed facet);
    event FacetReplaced(address indexed oldFacet, address indexed newFacet);
    event FacetRemoved(address indexed facet);

    // ═══════════════════════════════════════════════════════════════
    //                    DIAMOND (built-in)
    // ═══════════════════════════════════════════════════════════════

    // ── Governance ──

    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function transferAdmin(address newAdmin) external;
    function acceptAdmin() external;
    function upgradeDiamond(
        address[] calldata addFacets,
        address[] calldata removeFacets,
        ReplaceAction[] calldata replaceFacets
    ) external;

    // ── Configuration ──

    function setAssetConfig(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS) external;
    function setMaxSolverFeeBPS(uint256 maxSolverFeeBPS) external;
    function setMaxRefundFeeBPS(uint256 maxRefundFeeBPS) external;
    function setWithdrawalInputSettler(address settler) external;
    function setDepositOutputSettler(address settler) external;
    function setVettingFeeRecipient(address recipient) external;
    function setWithdrawalChainConfig(
        uint256 chainId,
        address outputSettler,
        address outputFillOracle,
        address inputFillOracle,
        uint32 fillDeadline,
        uint32 expiry
    ) external;
    function updateRoot(uint256 root, string calldata ipfsCID) external returns (uint256 index);
    function windDown() external;

    // ═══════════════════════════════════════════════════════════════
    //                     FACETS (delegatecall)
    // ═══════════════════════════════════════════════════════════════

    // ── Deposit ──

    function deposit(uint256 precommitment) external payable returns (uint256 commitment);

    // ── Crosschain Deposit ──

    function crosschainDeposit(address depositor, uint256 amount, uint256 precommitment)
        external
        payable
        returns (uint256 commitment);

    // ── Withdraw ──

    function withdraw(WithdrawData calldata data, WithdrawProofLib.WithdrawProof calldata proof) external;

    function crosschainWithdraw(
        CrosschainWithdrawData calldata data,
        CrosschainProofLib.CrosschainWithdrawProof calldata proof
    ) external;

    function withdraw2(WithdrawData calldata data, Withdraw2ProofLib.Withdraw2Proof calldata proof)
        external;

    function crosschainWithdraw2(
        CrosschainWithdrawData calldata data,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof calldata proof
    ) external;

    // ── Ragequit ──

    function ragequit(RagequitProofLib.RagequitProof calldata proof) external;

    // ── Refund ──

    function handleRefund(uint256 refundCommitment, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable;

    function handleRefund2(uint256 refundCommitment, address feeRecipient, uint256 refundFeeBPS, uint256 scope)
        external
        payable;

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
    function latestRoot() external view returns (uint256);
    function rootByIndex(uint256 index) external view returns (uint256);
    function associationSets(uint256 index) external view returns (uint256 root, string memory ipfsCID, uint256 timestamp);
    function assetConfig() external view returns (uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS);
    function maxSolverFeeBPS() external view returns (uint256);
    function maxRefundFeeBPS() external view returns (uint256);
    function vettingFeeRecipient() external view returns (address);
    function withdrawalInputSettler() external view returns (address);
    function depositOutputSettler() external view returns (address);
    function withdrawalChainConfig(uint256 chainId)
        external
        view
        returns (bool isConfigured, uint32 fillDeadline, uint32 expiry, address withdrawalOutputSettler, address outputFillOracle, address inputFillOracle);
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);

    // ── Loupe (ERC-8153) ──

    function facetAddress(bytes4 selector) external view returns (address);
    function facetAddresses() external view returns (address[] memory);
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory);
    function ROOT_HISTORY_SIZE() external pure returns (uint32);
    function MAX_TREE_DEPTH() external pure returns (uint32);

}
