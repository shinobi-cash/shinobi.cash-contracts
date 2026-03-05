// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Constants} from "./libraries/Constants.sol";
import {PoolStorageData, PoolStorageLib, AssociationSetData, WithdrawalChainConfig} from "./storage/PoolStorage.sol";
import {DiamondStorageData, DiamondStorageLib} from "./storage/DiamondStorage.sol";
import {AccessControlStorageData, AccessControlStorageLib} from "./storage/AccessControlStorage.sol";
import {DiamondOps} from "./libraries/DiamondOps.sol";
import {AccessControlOps} from "./libraries/AccessControlOps.sol";
import {PoolOps} from "./libraries/PoolOps.sol";
import {FacetBase} from "./facets/FacetBase.sol";

/// @title PoolDiamond - ERC-8153 diamond proxy for Shinobi Cash privacy pools
/// @notice Single-address pool with built-in governance, config, and views. Operational facets are delegatecalled via fallback.
contract PoolDiamond is FacetBase {
    struct InitParams {
        address asset;
        address admin;
        address aspPostman;
        address[] facets;
    }

    struct ReplaceAction {
        address oldFacet;
        address newFacet;
    }

    // ── Events ──

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
    event PoolDied();
    event VettingFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event AdminTransferStarted(address indexed currentAdmin, address indexed newAdmin);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    // ── Errors ──

    error FunctionNotFound(bytes4 selector);
    error InvalidIPFSCIDLength();
    error EmptyRoot();
    error InvalidFeeBPS();
    error InvalidAssetConfig();
    error InvalidAddress();
    error InvalidChainId();
    error DeadlineTooShort();
    error ExpiryBeforeFillDeadline();
    error NotPendingAdmin();

    // ── Constructor ──

    constructor(InitParams memory params) payable {
        PoolStorageData storage ps = PoolStorageLib.layout();
        ps.asset = params.asset;
        ps.scope =
            uint256(keccak256(abi.encodePacked(address(this), block.chainid, params.asset))) % Constants.SNARK_SCALAR_FIELD;

        // Set admin (single address, not a role)
        AccessControlStorageLib.layout().admin = params.admin;

        // ASP_POSTMAN_ROLE managed by admin
        AccessControlOps.grantRole(AccessControlStorageLib.ASP_POSTMAN_ROLE, params.aspPostman);

        // Register all operational facets via ERC-8153 on-chain discovery
        for (uint256 i; i < params.facets.length; ++i) {
            DiamondOps.addFacet(params.facets[i]);
        }
    }

    receive() external payable {}

    // ── Fallback (facet routing) ──

    fallback() external payable {
        DiamondStorageData storage ds = DiamondStorageLib.layout();
        address facet = ds.selectorToFacet[msg.sig];
        if (facet == address(0)) revert FunctionNotFound(msg.sig);

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }


    // ═══════════════════════════════════════════════════════════════
    //                         GOVERNANCE
    // ═══════════════════════════════════════════════════════════════

    function grantRole(bytes32 role, address account) external onlyAdmin {
        AccessControlOps.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        AccessControlOps.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        AccessControlOps.renounceRole(role, callerConfirmation);
    }

    // ── 2-Step Admin Transfer ──

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        AccessControlStorageLib.layout().pendingAdmin = newAdmin;
        emit AdminTransferStarted(msg.sender, newAdmin);
    }

    function acceptAdmin() external {
        AccessControlStorageData storage acs = AccessControlStorageLib.layout();
        if (msg.sender != acs.pendingAdmin) revert NotPendingAdmin();
        address oldAdmin = acs.admin;
        acs.admin = msg.sender;
        acs.pendingAdmin = address(0);
        emit AdminTransferred(oldAdmin, msg.sender);
    }

    // ── Diamond Upgrade (ERC-8153) ──

    function upgradeDiamond(
        address[] calldata addFacets,
        address[] calldata removeFacets,
        ReplaceAction[] calldata replaceFacets
    ) external onlyAdmin {
        for (uint256 i; i < removeFacets.length; ++i) {
            DiamondOps.removeFacet(removeFacets[i]);
        }
        for (uint256 i; i < replaceFacets.length; ++i) {
            DiamondOps.replaceFacet(replaceFacets[i].oldFacet, replaceFacets[i].newFacet);
        }
        for (uint256 i; i < addFacets.length; ++i) {
            DiamondOps.addFacet(addFacets[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONFIGURATION
    // ═══════════════════════════════════════════════════════════════

    function setAssetConfig(uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS)
        external
        onlyAdmin
    {
        if (minimumDepositAmount == 0 || maxRelayFeeBPS == 0) revert InvalidAssetConfig();
        if (vettingFeeBPS >= 10_000 || maxRelayFeeBPS >= 10_000) revert InvalidFeeBPS();
        PoolStorageData storage s = PoolStorageLib.layout();
        s.minimumDepositAmount = minimumDepositAmount;
        s.vettingFeeBPS = vettingFeeBPS;
        s.maxRelayFeeBPS = maxRelayFeeBPS;
        emit AssetConfigUpdated(minimumDepositAmount, vettingFeeBPS, maxRelayFeeBPS);
    }

    function setMaxSolverFeeBPS(uint256 newMaxSolverFeeBPS) external onlyAdmin {
        if (newMaxSolverFeeBPS >= 10_000) revert InvalidFeeBPS();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit MaxSolverFeeBPSUpdated(s.maxSolverFeeBPS, newMaxSolverFeeBPS);
        s.maxSolverFeeBPS = newMaxSolverFeeBPS;
    }

    function setMaxRefundFeeBPS(uint256 newMaxRefundFeeBPS) external onlyAdmin {
        if (newMaxRefundFeeBPS == 0 || newMaxRefundFeeBPS >= 10_000) revert InvalidFeeBPS();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit MaxRefundFeeBPSUpdated(s.maxRefundFeeBPS, newMaxRefundFeeBPS);
        s.maxRefundFeeBPS = newMaxRefundFeeBPS;
    }

    function setWithdrawalInputSettler(address settler) external onlyAdmin {
        if (settler == address(0)) revert InvalidAddress();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit WithdrawalInputSettlerUpdated(s.withdrawalInputSettler, settler);
        s.withdrawalInputSettler = settler;
    }

    function setDepositOutputSettler(address settler) external onlyAdmin {
        if (settler == address(0)) revert InvalidAddress();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit DepositOutputSettlerUpdated(s.depositOutputSettler, settler);
        s.depositOutputSettler = settler;
    }

    function setVettingFeeRecipient(address recipient) external onlyAdmin {
        if (recipient == address(0)) revert InvalidAddress();
        PoolStorageData storage s = PoolStorageLib.layout();
        emit VettingFeeRecipientUpdated(s.vettingFeeRecipient, recipient);
        s.vettingFeeRecipient = recipient;
    }

    function setWithdrawalChainConfig(
        uint256 chainId,
        address outputSettler,
        address outputFillOracle,
        address inputFillOracle,
        uint32 fillDeadline,
        uint32 expiry
    ) external onlyAdmin {
        if (chainId == 0) revert InvalidChainId();
        if (outputSettler == address(0) || outputFillOracle == address(0) || inputFillOracle == address(0)) {
            revert InvalidAddress();
        }
        if (fillDeadline < 300 || expiry < 300) revert DeadlineTooShort();
        if (expiry <= fillDeadline) revert ExpiryBeforeFillDeadline();

        PoolStorageData storage s = PoolStorageLib.layout();
        s.withdrawalChainConfig[chainId] = WithdrawalChainConfig({
            isConfigured: true,
            fillDeadline: fillDeadline,
            expiry: expiry,
            withdrawalOutputSettler: outputSettler,
            outputFillOracle: outputFillOracle,
            inputFillOracle: inputFillOracle
        });

        emit WithdrawalChainConfigured(chainId, fillDeadline, expiry, outputSettler, outputFillOracle, inputFillOracle);
    }

    // ── ASP Root ──

    function updateRoot(uint256 root, string calldata ipfsCID)
        external
        onlyRole(AccessControlStorageLib.ASP_POSTMAN_ROLE)
        returns (uint256 index)
    {
        if (root == 0) revert EmptyRoot();
        uint256 cidLength = bytes(ipfsCID).length;
        if (cidLength < 32 || cidLength > 64) revert InvalidIPFSCIDLength();

        PoolStorageData storage s = PoolStorageLib.layout();
        s.associationSets.push(AssociationSetData({root: root, ipfsCID: ipfsCID, timestamp: block.timestamp}));
        index = s.associationSets.length - 1;
        emit RootUpdated(root, ipfsCID, block.timestamp);
    }

    // ── Pool Lifecycle ──

    function windDown() external onlyAdmin {
        PoolStorageData storage s = PoolStorageLib.layout();
        s.dead = true;
        emit PoolDied();
    }

    // ═══════════════════════════════════════════════════════════════
    //                           VIEWS
    // ═══════════════════════════════════════════════════════════════

    // ── Pool Identity ──

    function ASSET() external view returns (address) {
        return PoolStorageLib.layout().asset;
    }

    function SCOPE() external view returns (uint256) {
        return PoolStorageLib.layout().scope;
    }

    // ── Merkle Tree State ──

    function nonce() external view returns (uint256) {
        return PoolStorageLib.layout().nonce;
    }

    function dead() external view returns (bool) {
        return PoolStorageLib.layout().dead;
    }

    function roots(uint256 index) external view returns (uint256) {
        return PoolStorageLib.layout().roots[index];
    }

    function currentRootIndex() external view returns (uint32) {
        return PoolStorageLib.layout().currentRootIndex;
    }

    function currentRoot() external view returns (uint256) {
        PoolStorageData storage s = PoolStorageLib.layout();
        return s.roots[s.currentRootIndex];
    }

    function currentTreeDepth() external view returns (uint256) {
        return PoolStorageLib.layout().merkleTree.depth;
    }

    function currentTreeSize() external view returns (uint256) {
        return PoolStorageLib.layout().merkleTree.size;
    }

    function nullifierHashes(uint256 hash) external view returns (bool) {
        return PoolStorageLib.layout().nullifierHashes[hash];
    }

    function depositors(uint256 label) external view returns (address) {
        return PoolStorageLib.layout().depositors[label];
    }

    function usedPrecommitments(uint256 precommitment) external view returns (bool) {
        return PoolStorageLib.layout().usedPrecommitments[precommitment];
    }

    // ── ASP State ──

    function latestRoot() external view returns (uint256) {
        return PoolOps.latestASPRoot(PoolStorageLib.layout());
    }

    function rootByIndex(uint256 index) external view returns (uint256) {
        return PoolStorageLib.layout().associationSets[index].root;
    }

    function associationSets(uint256 index)
        external
        view
        returns (uint256 root, string memory ipfsCID, uint256 timestamp)
    {
        AssociationSetData storage data = PoolStorageLib.layout().associationSets[index];
        return (data.root, data.ipfsCID, data.timestamp);
    }

    // ── Asset Config ──

    function assetConfig()
        external
        view
        returns (uint256 minimumDepositAmount, uint256 vettingFeeBPS, uint256 maxRelayFeeBPS)
    {
        PoolStorageData storage s = PoolStorageLib.layout();
        return (s.minimumDepositAmount, s.vettingFeeBPS, s.maxRelayFeeBPS);
    }

    function vettingFeeRecipient() external view returns (address) {
        return PoolStorageLib.layout().vettingFeeRecipient;
    }

    // ── Cross-chain Config ──

    function maxSolverFeeBPS() external view returns (uint256) {
        return PoolStorageLib.layout().maxSolverFeeBPS;
    }

    function maxRefundFeeBPS() external view returns (uint256) {
        return PoolStorageLib.layout().maxRefundFeeBPS;
    }

    function withdrawalInputSettler() external view returns (address) {
        return PoolStorageLib.layout().withdrawalInputSettler;
    }

    function depositOutputSettler() external view returns (address) {
        return PoolStorageLib.layout().depositOutputSettler;
    }

    function withdrawalChainConfig(uint256 chainId)
        external
        view
        returns (
            bool isConfigured,
            uint32 fillDeadline,
            uint32 expiry,
            address withdrawalOutputSettler,
            address outputFillOracle,
            address inputFillOracle
        )
    {
        WithdrawalChainConfig storage config = PoolStorageLib.layout().withdrawalChainConfig[chainId];
        return (
            config.isConfigured,
            config.fillDeadline,
            config.expiry,
            config.withdrawalOutputSettler,
            config.outputFillOracle,
            config.inputFillOracle
        );
    }

    // ── Access Control ──

    function admin() external view returns (address) {
        return AccessControlStorageLib.layout().admin;
    }

    function pendingAdmin() external view returns (address) {
        return AccessControlStorageLib.layout().pendingAdmin;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlOps.hasRole(role, account);
    }

    // ── ERC-8153 Loupe ──

    function facetAddress(bytes4 selector) external view returns (address) {
        return DiamondStorageLib.layout().selectorToFacet[selector];
    }

    function facetAddresses() external view returns (address[] memory) {
        return DiamondStorageLib.layout().facets;
    }

    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory) {
        return DiamondStorageLib.layout().facetSelectors[facet];
    }

    // ── Constants ──

    function ROOT_HISTORY_SIZE() external pure returns (uint32) {
        return PoolOps.ROOT_HISTORY_SIZE;
    }

    function MAX_TREE_DEPTH() external pure returns (uint32) {
        return PoolOps.MAX_TREE_DEPTH;
    }

}
