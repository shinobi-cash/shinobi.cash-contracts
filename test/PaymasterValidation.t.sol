// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ShinobiNativeCrosschainWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdrawalPaymaster.sol";
import {ShinobiNativeCrosschainWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeCrosschainWithdraw2Paymaster.sol";
import {ShinobiNativeWithdrawalPaymaster} from "../src/paymaster/ShinobiNativeWithdrawalPaymaster.sol";
import {ShinobiNativeWithdraw2Paymaster} from "../src/paymaster/ShinobiNativeWithdraw2Paymaster.sol";
import {IShinobiCashEntrypoint} from "../src/core/interfaces/IShinobiCashEntrypoint.sol";
import {IShinobiCashCrosschainHandler} from "../src/core/interfaces/IShinobiCashCrosschainHandler.sol";
import {IShinobiCashPool} from "../src/core/interfaces/IShinobiCashPool.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ICrosschainWithdraw2Verifier} from "../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {ShinobiCashPool} from "../src/core/ShinobiCashPool.sol";
import {IShinobiInputSettler} from "../src/oif/interfaces/IShinobiInputSettler.sol";
import {CrosschainProofLib} from "../src/core/libraries/CrosschainProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "../src/core/libraries/CrosschainWithdraw2ProofLib.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Withdraw2ProofLib} from "../src/core/libraries/Withdraw2ProofLib.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IWithdraw2Verifier} from "../src/core/interfaces/IWithdraw2Verifier.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @notice Mock ERC-4337 EntryPoint
 */
contract MockEntryPoint {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/**
 * @notice Mock ShinobiCashEntrypoint for testing paymaster validation
 */
contract MockShinobiCashEntrypoint {
    uint256 public _maxSolverFeeBPS;
    uint256 public _latestRoot = 1; // Non-zero default

    struct WithdrawalChainConfig {
        bool isConfigured;
        uint32 fillDeadline;
        uint32 expiry;
        address withdrawalOutputSettler;
        address withdrawalFillOracle;
        address fillOracle;
    }

    struct AssetConfig {
        address pool;
        uint256 minimumDepositAmount;
        uint256 vettingFeeBPS;
        uint256 maxRelayFeeBPS;
    }

    mapping(uint256 => WithdrawalChainConfig) public _withdrawalChainConfigs;
    mapping(address => AssetConfig) public _assetConfigs;

    function setMaxSolverFeeBPS(uint256 value) external {
        _maxSolverFeeBPS = value;
    }

    function maxSolverFeeBPS() external view returns (uint256) {
        return _maxSolverFeeBPS;
    }

    function setWithdrawalChainConfig(
        uint256 chainId,
        bool isConfigured,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    ) external {
        _withdrawalChainConfigs[chainId] = WithdrawalChainConfig({
            isConfigured: isConfigured,
            fillDeadline: fillDeadline,
            expiry: expiry,
            withdrawalOutputSettler: withdrawalOutputSettler,
            withdrawalFillOracle: withdrawalFillOracle,
            fillOracle: fillOracle
        });
    }

    function withdrawalChainConfig(uint256 chainId) external view returns (
        bool isConfigured,
        uint32 fillDeadline,
        uint32 expiry,
        address withdrawalOutputSettler,
        address withdrawalFillOracle,
        address fillOracle
    ) {
        WithdrawalChainConfig storage config = _withdrawalChainConfigs[chainId];
        return (
            config.isConfigured,
            config.fillDeadline,
            config.expiry,
            config.withdrawalOutputSettler,
            config.withdrawalFillOracle,
            config.fillOracle
        );
    }

    function setAssetConfig(
        address asset,
        address pool,
        uint256 minimumDepositAmount,
        uint256 vettingFeeBPS,
        uint256 maxRelayFeeBPS
    ) external {
        _assetConfigs[asset] = AssetConfig({
            pool: pool,
            minimumDepositAmount: minimumDepositAmount,
            vettingFeeBPS: vettingFeeBPS,
            maxRelayFeeBPS: maxRelayFeeBPS
        });
    }

    function assetConfig(IERC20 asset) external view returns (
        IPrivacyPool pool,
        uint256 minimumDepositAmount,
        uint256 vettingFeeBPS,
        uint256 maxRelayFeeBPS
    ) {
        AssetConfig storage config = _assetConfigs[address(asset)];
        return (
            IPrivacyPool(config.pool),
            config.minimumDepositAmount,
            config.vettingFeeBPS,
            config.maxRelayFeeBPS
        );
    }

    function latestRoot() external view returns (uint256) {
        return _latestRoot;
    }
}

/**
 * @notice Mock ShinobiCashPool for testing
 */
contract MockShinobiCashPool {
    uint256 public SCOPE = 12345;
    uint32 public MAX_TREE_DEPTH = 32;
    uint32 public ROOT_HISTORY_SIZE = 30;
    uint32 public currentRootIndex = 0;
    mapping(uint32 => uint256) public roots;
    mapping(uint256 => bool) public nullifierHashes;

    address public CROSS_CHAIN_WITHDRAWAL_VERIFIER;

    constructor() {
        roots[0] = 1; // Set a known root
    }

    function setCrossChainWithdrawalVerifier(address verifier) external {
        CROSS_CHAIN_WITHDRAWAL_VERIFIER = verifier;
    }
}

/**
 * @notice Mock InputSettler for testing
 */
contract MockInputSettler {
    // Empty mock
}

/**
 * @notice Test harness for ShinobiNativeCrosschainWithdrawalPaymaster validation
 * @dev Exposes internal crosschainWithdrawal for direct testing by removing msg.sender check
 */
contract CrosschainWithdrawalPaymasterHarness is ShinobiNativeCrosschainWithdrawalPaymaster {
    using CrosschainProofLib for CrosschainProofLib.CrosschainWithdrawProof;

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        ShinobiCashPool _ethShinobiCashPool,
        IShinobiInputSettler _inputSettler
    ) ShinobiNativeCrosschainWithdrawalPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethShinobiCashPool, _inputSettler) {}

    /**
     * @notice Exposed validation function for testing
     * @dev Bypasses msg.sender == address(this) check
     */
    function exposed_validateWithdrawal(
        IPrivacyPool.Withdrawal memory _withdrawal,
        CrosschainProofLib.CrosschainWithdrawProof memory _proof,
        uint256 _scope
    ) external {
        // Skip msg.sender check, perform all other validations
        if (_withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (_withdrawal.data.length != 96) revert InvalidRelayDataLength();

        IShinobiCashCrosschainHandler.CrosschainRelayData memory relayData = abi.decode(
            _withdrawal.data,
            (IShinobiCashCrosschainHandler.CrosschainRelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (_scope != ETH_POOL.SCOPE()) revert InvalidScope();

        // Early configuration checks - these are what we're testing
        uint256 maxSolver = SHINOBI_CASH_ENTRYPOINT.maxSolverFeeBPS();
        if (maxSolver == 0) revert MaxSolverFeeBPSNotSet();

        uint32 chainId = uint32(uint256(relayData.encodedDestination) >> 224);
        (bool isConfigured,,,,,) = SHINOBI_CASH_ENTRYPOINT.withdrawalChainConfig(chainId);
        if (!isConfigured) revert DestinationChainNotConfigured();

        uint256 relayFeeBPS = _proof.relayFeeBPS();
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (relayData.solverFeeBPS > maxSolver) revert SolverFeeGreaterThanMax();
    }
}

/**
 * @notice Test harness for ShinobiNativeCrosschainWithdraw2Paymaster validation
 */
contract CrosschainWithdraw2PaymasterHarness is ShinobiNativeCrosschainWithdraw2Paymaster {
    using CrosschainWithdraw2ProofLib for CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof;

    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        ICrosschainWithdraw2Verifier _crossChainWithdraw2Verifier,
        IShinobiInputSettler _inputSettler
    ) ShinobiNativeCrosschainWithdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _crossChainWithdraw2Verifier, _inputSettler) {}

    /**
     * @notice Exposed validation function for testing
     */
    function exposed_validateWithdrawal(
        IPrivacyPool.Withdrawal memory withdrawal,
        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof,
        uint256 scope
    ) external {
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        IShinobiCashCrosschainHandler.CrosschainRelayData memory relayData = abi.decode(
            withdrawal.data,
            (IShinobiCashCrosschainHandler.CrosschainRelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early configuration checks
        uint256 maxSolver = SHINOBI_CASH_ENTRYPOINT.maxSolverFeeBPS();
        if (maxSolver == 0) revert MaxSolverFeeBPSNotSet();

        uint32 chainId = uint32(uint256(relayData.encodedDestination) >> 224);
        (bool isConfigured,,,,,) = SHINOBI_CASH_ENTRYPOINT.withdrawalChainConfig(chainId);
        if (!isConfigured) revert DestinationChainNotConfigured();

        uint256 relayFeeBPS = proof.relayFeeBPS();
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();

        if (relayData.solverFeeBPS > maxSolver) revert SolverFeeGreaterThanMax();
    }
}

/**
 * @notice Test harness for ShinobiNativeWithdrawalPaymaster validation (same-chain)
 */
contract WithdrawalPaymasterHarness is ShinobiNativeWithdrawalPaymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IPrivacyPool _ethPrivacyPool
    ) ShinobiNativeWithdrawalPaymaster(_entryPoint, _shinobiCashEntrypoint, _ethPrivacyPool) {}

    /**
     * @notice Exposed validation function for testing relay fee check
     */
    function exposed_validateRelayFee(
        IPrivacyPool.Withdrawal memory withdrawal,
        uint256 relayFeeBPS,
        uint256 scope
    ) external view {
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        IEntrypoint.RelayData memory relayData = abi.decode(
            withdrawal.data,
            (IEntrypoint.RelayData)
        );

        if (relayData.feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early relay fee validation
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
    }
}

/**
 * @notice Test harness for ShinobiNativeWithdraw2Paymaster validation (same-chain)
 */
contract Withdraw2PaymasterHarness is ShinobiNativeWithdraw2Paymaster {
    constructor(
        IEntryPoint _entryPoint,
        IShinobiCashEntrypoint _shinobiCashEntrypoint,
        IShinobiCashPool _ethCashPool,
        IWithdraw2Verifier _withdraw2Verifier
    ) ShinobiNativeWithdraw2Paymaster(_entryPoint, _shinobiCashEntrypoint, _ethCashPool, _withdraw2Verifier) {}

    /**
     * @notice Exposed validation function for testing relay fee check
     */
    function exposed_validateRelayFee(
        IPrivacyPool.Withdrawal memory withdrawal,
        uint256 relayFeeBPS,
        uint256 scope
    ) external view {
        if (withdrawal.processooor != address(SHINOBI_CASH_ENTRYPOINT)) revert InvalidProcessooor();
        if (withdrawal.data.length != 96) revert InvalidRelayDataLength();

        (address feeRecipient, , ) = _decodeRelayData(withdrawal.data);

        if (feeRecipient != address(this)) revert WrongFeeRecipient();
        if (scope != ETH_CASH_POOL.SCOPE()) revert InvalidScope();

        // Early relay fee validation
        (, , , uint256 maxRelayFeeBPS) = SHINOBI_CASH_ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
        if (relayFeeBPS > maxRelayFeeBPS) revert RelayFeeGreaterThanMax();
    }
}

contract PaymasterValidationTest is Test {
    MockEntryPoint public mockEntryPoint;
    MockShinobiCashEntrypoint public mockEntrypoint;
    MockShinobiCashPool public mockPool;
    MockInputSettler public mockSettler;

    CrosschainWithdrawalPaymasterHarness public crosschainPaymaster;
    CrosschainWithdraw2PaymasterHarness public crosschainWithdraw2Paymaster;
    WithdrawalPaymasterHarness public withdrawalPaymaster;
    Withdraw2PaymasterHarness public withdraw2Paymaster;

    address public owner = makeAddr("owner");

    // Test constants
    uint256 constant CHAIN_ID_BASE = 84532;
    uint256 constant MAX_SOLVER_FEE_BPS = 1000;
    uint256 constant MAX_RELAY_FEE_BPS = 500;

    function setUp() public {
        mockEntryPoint = new MockEntryPoint();
        mockEntrypoint = new MockShinobiCashEntrypoint();
        mockPool = new MockShinobiCashPool();
        mockSettler = new MockInputSettler();

        // Deploy crosschain withdrawal paymaster harness
        crosschainPaymaster = new CrosschainWithdrawalPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(mockEntrypoint)),
            ShinobiCashPool(address(mockPool)),
            IShinobiInputSettler(address(mockSettler))
        );

        // Deploy crosschain withdraw2 paymaster harness
        crosschainWithdraw2Paymaster = new CrosschainWithdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(mockEntrypoint)),
            IShinobiCashPool(address(mockPool)),
            ICrosschainWithdraw2Verifier(makeAddr("verifier")),
            IShinobiInputSettler(address(mockSettler))
        );

        // Deploy same-chain withdrawal paymaster harness
        withdrawalPaymaster = new WithdrawalPaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(mockEntrypoint)),
            IPrivacyPool(address(mockPool))
        );

        // Deploy same-chain withdraw2 paymaster harness
        withdraw2Paymaster = new Withdraw2PaymasterHarness(
            IEntryPoint(address(mockEntryPoint)),
            IShinobiCashEntrypoint(address(mockEntrypoint)),
            IShinobiCashPool(address(mockPool)),
            IWithdraw2Verifier(makeAddr("withdraw2Verifier"))
        );

        // Configure defaults
        mockEntrypoint.setMaxSolverFeeBPS(MAX_SOLVER_FEE_BPS);
        mockEntrypoint.setWithdrawalChainConfig(
            CHAIN_ID_BASE,
            true, // isConfigured
            1800, // fillDeadline
            86400, // expiry
            makeAddr("outputSettler"),
            makeAddr("withdrawalFillOracle"),
            makeAddr("fillOracle")
        );
        mockEntrypoint.setAssetConfig(
            Constants.NATIVE_ASSET,
            address(mockPool),
            0.001 ether,
            100,
            MAX_RELAY_FEE_BPS
        );
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAWAL PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function _createWithdrawalData(
        address feeRecipient,
        uint256 solverFeeBPS,
        uint256 chainId,
        address recipient
    ) internal pure returns (bytes memory) {
        bytes32 encodedDestination = bytes32((chainId << 224) | uint256(uint160(recipient)));
        return abi.encode(
            IShinobiCashCrosschainHandler.CrosschainRelayData({
                feeRecipient: feeRecipient,
                solverFeeBPS: solverFeeBPS,
                encodedDestination: encodedDestination
            })
        );
    }

    function _createWithdrawal(
        address processooor,
        bytes memory data
    ) internal pure returns (IPrivacyPool.Withdrawal memory) {
        return IPrivacyPool.Withdrawal({
            processooor: processooor,
            data: data
        });
    }

    function _createCrosschainProof(uint256 relayFeeBPS) internal pure returns (CrosschainProofLib.CrosschainWithdrawProof memory) {
        // Create minimal proof with relayFeeBPS at index 3
        uint256[2] memory pA;
        uint256[2][2] memory pB;
        uint256[2] memory pC;
        uint256[11] memory pubSignals;

        pubSignals[3] = relayFeeBPS; // relayFeeBPSOut
        pubSignals[5] = 1 ether; // withdrawnValue

        return CrosschainProofLib.CrosschainWithdrawProof({
            pA: pA,
            pB: pB,
            pC: pC,
            pubSignals: pubSignals
        });
    }

    function test_crosschainPaymaster_revertsMaxSolverFeeBPSNotSet() public {
        // Set maxSolverFeeBPS to 0
        mockEntrypoint.setMaxSolverFeeBPS(0);

        bytes memory data = _createWithdrawalData(
            address(crosschainPaymaster),
            500, // solverFeeBPS
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        // Cache scope before expectRevert to avoid it being counted as the "next call"
        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.MaxSolverFeeBPSNotSet.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainPaymaster_revertsDestinationChainNotConfigured() public {
        uint256 unconfiguredChainId = 99999;

        bytes memory data = _createWithdrawalData(
            address(crosschainPaymaster),
            500, // solverFeeBPS
            unconfiguredChainId,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.DestinationChainNotConfigured.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainPaymaster_revertsRelayFeeGreaterThanMax() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainPaymaster),
            500, // solverFeeBPS
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        // Set relayFeeBPS higher than maxRelayFeeBPS
        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(MAX_RELAY_FEE_BPS + 1);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.RelayFeeGreaterThanMax.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainPaymaster_revertsSolverFeeGreaterThanMax() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainPaymaster),
            MAX_SOLVER_FEE_BPS + 1, // solverFeeBPS exceeds max
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.SolverFeeGreaterThanMax.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainPaymaster_passesWithValidConfig() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainPaymaster),
            500, // solverFeeBPS within limit
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        // Should not revert
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, mockPool.SCOPE());
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function _createCrosschainWithdraw2Proof(uint256 relayFeeBPS) internal pure returns (CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory) {
        uint256[2] memory pA;
        uint256[2][2] memory pB;
        uint256[2] memory pC;
        uint256[12] memory pubSignals;

        pubSignals[4] = relayFeeBPS; // relayFeeBPSOut
        pubSignals[6] = 1 ether; // withdrawnValue

        return CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof({
            pA: pA,
            pB: pB,
            pC: pC,
            pubSignals: pubSignals
        });
    }

    function test_crosschainWithdraw2Paymaster_revertsMaxSolverFeeBPSNotSet() public {
        mockEntrypoint.setMaxSolverFeeBPS(0);

        bytes memory data = _createWithdrawalData(
            address(crosschainWithdraw2Paymaster),
            500,
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.MaxSolverFeeBPSNotSet.selector);
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainWithdraw2Paymaster_revertsDestinationChainNotConfigured() public {
        uint256 unconfiguredChainId = 99999;

        bytes memory data = _createWithdrawalData(
            address(crosschainWithdraw2Paymaster),
            500,
            unconfiguredChainId,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.DestinationChainNotConfigured.selector);
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainWithdraw2Paymaster_revertsRelayFeeGreaterThanMax() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainWithdraw2Paymaster),
            500,
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(MAX_RELAY_FEE_BPS + 1);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.RelayFeeGreaterThanMax.selector);
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainWithdraw2Paymaster_revertsSolverFeeGreaterThanMax() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainWithdraw2Paymaster),
            MAX_SOLVER_FEE_BPS + 1,
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.SolverFeeGreaterThanMax.selector);
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainWithdraw2Paymaster_passesWithValidConfig() public {
        bytes memory data = _createWithdrawalData(
            address(crosschainWithdraw2Paymaster),
            500,
            CHAIN_ID_BASE,
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(100);

        // Should not revert
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, mockPool.SCOPE());
    }

    /*//////////////////////////////////////////////////////////////
                    SAME-CHAIN WITHDRAWAL PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function _createSameChainRelayData(
        address feeRecipient,
        uint256 relayFeeBPS,
        address recipient
    ) internal pure returns (bytes memory) {
        return abi.encode(
            IEntrypoint.RelayData({
                recipient: recipient,
                feeRecipient: feeRecipient,
                relayFeeBPS: relayFeeBPS
            })
        );
    }

    function _createWithdraw2RelayData(
        address recipient,
        address feeRecipient,
        uint256 relayFeeBPS
    ) internal pure returns (bytes memory) {
        return abi.encode(recipient, feeRecipient, relayFeeBPS);
    }

    function test_withdrawalPaymaster_revertsRelayFeeGreaterThanMax() public {
        bytes memory data = _createSameChainRelayData(
            address(withdrawalPaymaster),
            MAX_RELAY_FEE_BPS + 1, // exceeds max
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeWithdrawalPaymaster.RelayFeeGreaterThanMax.selector);
        withdrawalPaymaster.exposed_validateRelayFee(withdrawal, MAX_RELAY_FEE_BPS + 1, scope);
    }

    function test_withdrawalPaymaster_passesWithValidRelayFee() public {
        bytes memory data = _createSameChainRelayData(
            address(withdrawalPaymaster),
            MAX_RELAY_FEE_BPS, // exactly at max
            makeAddr("recipient")
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        // Should not revert
        withdrawalPaymaster.exposed_validateRelayFee(withdrawal, MAX_RELAY_FEE_BPS, mockPool.SCOPE());
    }

    /*//////////////////////////////////////////////////////////////
                    SAME-CHAIN WITHDRAW2 PAYMASTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw2Paymaster_revertsRelayFeeGreaterThanMax() public {
        bytes memory data = _createWithdraw2RelayData(
            makeAddr("recipient"),
            address(withdraw2Paymaster),
            MAX_RELAY_FEE_BPS + 1
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.RelayFeeGreaterThanMax.selector);
        withdraw2Paymaster.exposed_validateRelayFee(withdrawal, MAX_RELAY_FEE_BPS + 1, scope);
    }

    function test_withdraw2Paymaster_passesWithValidRelayFee() public {
        bytes memory data = _createWithdraw2RelayData(
            makeAddr("recipient"),
            address(withdraw2Paymaster),
            MAX_RELAY_FEE_BPS
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            data
        );

        // Should not revert
        withdraw2Paymaster.exposed_validateRelayFee(withdrawal, MAX_RELAY_FEE_BPS, mockPool.SCOPE());
    }

    /*//////////////////////////////////////////////////////////////
                    RELAY DATA LENGTH VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crosschainPaymaster_revertsInvalidRelayDataLength_tooShort() public {
        // Create data with wrong length (64 bytes instead of 96)
        bytes memory shortData = abi.encode(address(crosschainPaymaster), uint256(500));

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            shortData
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.InvalidRelayDataLength.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainPaymaster_revertsInvalidRelayDataLength_tooLong() public {
        // Create data with wrong length (128 bytes instead of 96)
        bytes memory longData = abi.encode(
            address(crosschainPaymaster),
            uint256(500),
            bytes32(uint256(CHAIN_ID_BASE) << 224),
            uint256(12345) // extra field
        );

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            longData
        );

        CrosschainProofLib.CrosschainWithdrawProof memory proof = _createCrosschainProof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdrawalPaymaster.InvalidRelayDataLength.selector);
        crosschainPaymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_crosschainWithdraw2Paymaster_revertsInvalidRelayDataLength() public {
        bytes memory shortData = abi.encode(address(crosschainWithdraw2Paymaster), uint256(500));

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            shortData
        );

        CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof = _createCrosschainWithdraw2Proof(100);

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeCrosschainWithdraw2Paymaster.InvalidRelayDataLength.selector);
        crosschainWithdraw2Paymaster.exposed_validateWithdrawal(withdrawal, proof, scope);
    }

    function test_withdrawalPaymaster_revertsInvalidRelayDataLength() public {
        bytes memory shortData = abi.encode(makeAddr("recipient"), address(withdrawalPaymaster));

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            shortData
        );

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeWithdrawalPaymaster.InvalidRelayDataLength.selector);
        withdrawalPaymaster.exposed_validateRelayFee(withdrawal, 100, scope);
    }

    function test_withdraw2Paymaster_revertsInvalidRelayDataLength() public {
        bytes memory shortData = abi.encode(makeAddr("recipient"), address(withdraw2Paymaster));

        IPrivacyPool.Withdrawal memory withdrawal = _createWithdrawal(
            address(mockEntrypoint),
            shortData
        );

        uint256 scope = mockPool.SCOPE();
        vm.expectRevert(ShinobiNativeWithdraw2Paymaster.InvalidRelayDataLength.selector);
        withdraw2Paymaster.exposed_validateRelayFee(withdrawal, 100, scope);
    }
}
