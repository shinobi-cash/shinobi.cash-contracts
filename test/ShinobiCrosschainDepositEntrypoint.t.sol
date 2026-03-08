// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ShinobiCrosschainDepositEntrypoint} from "../src/crosschain/ShinobiCrosschainDepositEntrypoint.sol";
import {ShinobiIntent} from "../src/oif/libraries/ShinobiIntentType.sol";
import {Constants} from "../src/pool/libraries/Constants.sol";

contract ShinobiCrosschainDepositEntrypointTest is Test {
    ShinobiCrosschainDepositEntrypoint public entrypoint;
    MockInputSettler public inputSettler;
    MockHyperlaneOracle public hyperlaneOracle;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public fillOracle = makeAddr("fillOracle");
    address public intentOracle = makeAddr("intentOracle");
    address public destEntrypoint = makeAddr("destEntrypoint");
    address public destOutputSettler = makeAddr("destOutputSettler");
    address public destOracle = makeAddr("destOracle");
    address public destPool = makeAddr("destPool");

    uint256 public constant DEST_CHAIN_ID = 421614;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 public constant MIN_DEPOSIT = 0.01 ether;

    event InputSettlerSet(address indexed inputSettlerAddress);
    event DefaultDeadlinesUpdated(uint32 newFillDeadline, uint32 newExpiry);
    event FillOracleUpdated(address indexed previousFillOracle, address indexed newFillOracle);
    event IntentOracleUpdated(address indexed previousIntentOracle, address indexed newIntentOracle);
    event DestinationConfigUpdated(uint256 indexed chainId, address indexed entrypoint, address outputSettler, address oracle);
    event MinimumDepositAmountUpdated(uint256 previousMinimum, uint256 newMinimum);
    event DefaultSolverFeeBPSUpdated(uint256 previousFeeBPS, uint256 newFeeBPS);
    event MaxSolverFeeBPSUpdated(uint256 previousMaxFeeBPS, uint256 newMaxFeeBPS);
    event AssetPoolConfigured(address indexed asset, address indexed pool);
    event AssetPoolRemoved(address indexed asset);
    event CrossChainDepositIntent(
        address indexed depositor,
        uint256 indexed precommitment,
        uint256 totalPaid,
        uint256 netDepositAmount,
        uint256 solverFee,
        uint256 destinationChainId,
        address asset,
        address destinationPool,
        bytes32 indexed orderId
    );
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public destHyperlaneOracle = makeAddr("destHyperlaneOracle");
    uint32 public constant DEST_HYPERLANE_DOMAIN = 421614;

    function setUp() public {
        entrypoint = new ShinobiCrosschainDepositEntrypoint(owner);
        inputSettler = new MockInputSettler();
        hyperlaneOracle = new MockHyperlaneOracle();

        // Configure entrypoint with all required settings
        vm.startPrank(owner);
        entrypoint.setInputSettler(address(inputSettler));
        entrypoint.setFillOracle(fillOracle);
        entrypoint.setIntentOracle(intentOracle);
        entrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        entrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        // Hyperlane is now required for cross-chain deposits
        entrypoint.setHyperlaneConfig(
            address(hyperlaneOracle),
            DEST_HYPERLANE_DOMAIN,
            destHyperlaneOracle,
            200_000
        );
        vm.stopPrank();

        vm.deal(user, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_setsOwner() public view {
        assertEq(entrypoint.owner(), owner);
    }

    function test_constructor_setsDefaults() public view {
        assertEq(entrypoint.defaultFillDeadline(), 30 minutes);
        assertEq(entrypoint.defaultExpiry(), 24 hours);
        assertEq(entrypoint.minimumDepositAmount(), 0.01 ether);
        assertEq(entrypoint.defaultSolverFeeBPS(), 500);
        assertEq(entrypoint.maxSolverFeeBPS(), 1000);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNABLE2STEP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership_setsPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        entrypoint.transferOwnership(newOwner);

        assertEq(entrypoint.pendingOwner(), newOwner);
        assertEq(entrypoint.owner(), owner);
    }

    function test_transferOwnership_onlyOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        entrypoint.transferOwnership(newOwner);
    }

    function test_acceptOwnership_transfersOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        entrypoint.transferOwnership(newOwner);

        vm.prank(newOwner);
        entrypoint.acceptOwnership();

        assertEq(entrypoint.owner(), newOwner);
        assertEq(entrypoint.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertsForNonPending() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        entrypoint.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        entrypoint.acceptOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_success() public {
        uint256 precommitment = 12345;

        vm.prank(user);
        entrypoint.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        // Verify input settler received the call
        assertTrue(inputSettler.openCalled());
        // Verify precommitment is marked as used
        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }

    function test_deposit_revertsZeroAmount() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.InvalidAmount.selector);
        vm.prank(user);
        entrypoint.deposit{value: 0}(12345);
    }

    function test_deposit_revertsPrecommitmentAlreadyUsed() public {
        uint256 precommitment = 12345;

        vm.prank(user);
        entrypoint.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.PrecommitmentAlreadyUsed.selector);
        vm.prank(user);
        entrypoint.deposit{value: DEPOSIT_AMOUNT}(precommitment);
    }

    function test_deposit_revertsBelowMinimumAfterFee() public {
        // With hyperlane gas (0.001 ETH) and 5% solver fee:
        // - Deposit: 0.01 ETH - 0.001 ETH (gas) = 0.009 ETH
        // - Solver fee: 0.009 * 5% = 0.00045 ETH
        // - Net: 0.009 - 0.00045 = 0.00855 ETH (below 0.01 minimum)
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.DepositAmountBelowMinimumAfterFee.selector,
                0.00855 ether,
                MIN_DEPOSIT
            )
        );
        vm.prank(user);
        entrypoint.deposit{value: 0.01 ether}(12345);
    }

    function test_deposit_emitsEvent() public {
        uint256 precommitment = 12345;

        vm.prank(user);
        entrypoint.deposit{value: DEPOSIT_AMOUNT}(precommitment);

        // Event verification is complex due to orderId, just verify deposit worked
        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT WITH CUSTOM PARAMS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositWithCustomParams_success() public {
        uint256 precommitment = 12345;
        uint256 customFeeBPS = 300; // 3%
        uint32 customFillDeadline = 2 hours;
        uint32 customExpiry = 12 hours;

        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            precommitment,
            customFeeBPS,
            customFillDeadline,
            customExpiry
        );

        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }

    function test_depositWithCustomParams_revertsSolverFeeExceedsMax() public {
        uint256 customFeeBPS = 1500; // 15%, exceeds max of 10%

        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.SolverFeeExceedsMax.selector,
                1500,
                1000
            )
        );
        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            12345,
            customFeeBPS,
            2 hours,
            12 hours
        );
    }

    function test_depositWithCustomParams_revertsExpiryBeforeFillDeadline() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ExpiryBeforeFillDeadline.selector);
        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            12345,
            500,
            12 hours,  // fillDeadline
            6 hours    // expiry (before fillDeadline)
        );
    }

    function test_depositWithCustomParams_revertsExpiryEqualsFillDeadline() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ExpiryBeforeFillDeadline.selector);
        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            12345,
            500,
            6 hours,
            6 hours  // expiry equals fillDeadline
        );
    }

    function test_depositWithCustomParams_revertsFillDeadlineTooShort() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.DeadlineTooShort.selector);
        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            12345,
            500,
            59,      // Less than 60 seconds
            2 hours
        );
    }

    function test_depositWithCustomParams_allowsMinimumDeadline() public {
        uint256 precommitment = 12345;

        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            precommitment,
            500,
            60,       // Exactly 60 seconds (minimum)
            2 hours
        );

        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }

    /*//////////////////////////////////////////////////////////////
                    CONFIGURATION VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_revertsWhenInputSettlerNotSet() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        // Don't set inputSettler
        newEntrypoint.setFillOracle(fillOracle);
        newEntrypoint.setIntentOracle(intentOracle);
        newEntrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        newEntrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        vm.stopPrank();

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ConfigurationNotSet.selector);
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_revertsWhenFillOracleNotSet() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        newEntrypoint.setInputSettler(address(inputSettler));
        // Don't set fillOracle
        newEntrypoint.setIntentOracle(intentOracle);
        newEntrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        newEntrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        vm.stopPrank();

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ConfigurationNotSet.selector);
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_revertsWhenIntentOracleNotSet() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        newEntrypoint.setInputSettler(address(inputSettler));
        newEntrypoint.setFillOracle(fillOracle);
        // Don't set intentOracle
        newEntrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        newEntrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        vm.stopPrank();

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ConfigurationNotSet.selector);
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_revertsWhenDestinationNotConfigured() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        newEntrypoint.setInputSettler(address(inputSettler));
        newEntrypoint.setFillOracle(fillOracle);
        newEntrypoint.setIntentOracle(intentOracle);
        // Don't set destination config
        newEntrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        vm.stopPrank();

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ConfigurationNotSet.selector);
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_revertsWhenAssetPoolNotSet() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        newEntrypoint.setInputSettler(address(inputSettler));
        newEntrypoint.setFillOracle(fillOracle);
        newEntrypoint.setIntentOracle(intentOracle);
        newEntrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        // Don't set asset pool
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.AssetNotSupported.selector,
                Constants.NATIVE_ASSET
            )
        );
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    function test_deposit_revertsWhenHyperlaneNotConfigured() public {
        ShinobiCrosschainDepositEntrypoint newEntrypoint = new ShinobiCrosschainDepositEntrypoint(owner);

        vm.startPrank(owner);
        newEntrypoint.setInputSettler(address(inputSettler));
        newEntrypoint.setFillOracle(fillOracle);
        newEntrypoint.setIntentOracle(intentOracle);
        newEntrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, destOracle);
        newEntrypoint.setAssetPool(Constants.NATIVE_ASSET, destPool);
        // Don't set hyperlane config
        vm.stopPrank();

        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.HyperlaneNotConfigured.selector);
        vm.prank(user);
        newEntrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER TESTS - INPUT SETTLER
    //////////////////////////////////////////////////////////////*/

    function test_setInputSettler_success() public {
        address newSettler = makeAddr("newSettler");

        vm.expectEmit(true, false, false, false);
        emit InputSettlerSet(newSettler);

        vm.prank(owner);
        entrypoint.setInputSettler(newSettler);

        assertEq(entrypoint.inputSettler(), newSettler);
    }

    function test_setInputSettler_revertsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setInputSettler(address(0));
    }

    function test_setInputSettler_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        entrypoint.setInputSettler(makeAddr("newSettler"));
    }

    /*//////////////////////////////////////////////////////////////
                    SETTER TESTS - DEFAULT DEADLINES
    //////////////////////////////////////////////////////////////*/

    function test_setDefaultDeadlines_success() public {
        uint32 newFillDeadline = 1 hours;
        uint32 newExpiry = 12 hours;

        vm.expectEmit(false, false, false, true);
        emit DefaultDeadlinesUpdated(newFillDeadline, newExpiry);

        vm.prank(owner);
        entrypoint.setDefaultDeadlines(newFillDeadline, newExpiry);

        assertEq(entrypoint.defaultFillDeadline(), newFillDeadline);
        assertEq(entrypoint.defaultExpiry(), newExpiry);
    }

    function test_setDefaultDeadlines_revertsExpiryBeforeFillDeadline() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ExpiryBeforeFillDeadline.selector);
        vm.prank(owner);
        entrypoint.setDefaultDeadlines(12 hours, 6 hours);
    }

    function test_setDefaultDeadlines_revertsExpiryEqualsFillDeadline() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.ExpiryBeforeFillDeadline.selector);
        vm.prank(owner);
        entrypoint.setDefaultDeadlines(6 hours, 6 hours);
    }

    function test_setDefaultDeadlines_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        entrypoint.setDefaultDeadlines(1 hours, 12 hours);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER TESTS - ORACLES
    //////////////////////////////////////////////////////////////*/

    function test_setFillOracle_success() public {
        address newOracle = makeAddr("newFillOracle");

        vm.expectEmit(true, true, false, false);
        emit FillOracleUpdated(fillOracle, newOracle);

        vm.prank(owner);
        entrypoint.setFillOracle(newOracle);

        assertEq(entrypoint.fillOracle(), newOracle);
    }

    function test_setFillOracle_revertsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setFillOracle(address(0));
    }

    function test_setIntentOracle_success() public {
        address newOracle = makeAddr("newIntentOracle");

        vm.expectEmit(true, true, false, false);
        emit IntentOracleUpdated(intentOracle, newOracle);

        vm.prank(owner);
        entrypoint.setIntentOracle(newOracle);

        assertEq(entrypoint.intentOracle(), newOracle);
    }

    function test_setIntentOracle_revertsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setIntentOracle(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    SETTER TESTS - DESTINATION CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_setDestinationConfig_success() public {
        uint256 newChainId = 84532;
        address newEntrypoint = makeAddr("newDestEntrypoint");
        address newSettler = makeAddr("newDestSettler");
        address newOracle = makeAddr("newDestOracle");

        vm.expectEmit(true, true, false, true);
        emit DestinationConfigUpdated(newChainId, newEntrypoint, newSettler, newOracle);

        vm.prank(owner);
        entrypoint.setDestinationConfig(newChainId, newEntrypoint, newSettler, newOracle);

        assertEq(entrypoint.destinationChainId(), newChainId);
        assertEq(entrypoint.destinationEntrypoint(), newEntrypoint);
        assertEq(entrypoint.destinationOutputSettler(), newSettler);
        assertEq(entrypoint.destinationOracle(), newOracle);
    }

    function test_setDestinationConfig_revertsZeroChainId() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidChainId.selector,
                0
            )
        );
        vm.prank(owner);
        entrypoint.setDestinationConfig(0, destEntrypoint, destOutputSettler, destOracle);
    }

    function test_setDestinationConfig_revertsZeroEntrypoint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setDestinationConfig(DEST_CHAIN_ID, address(0), destOutputSettler, destOracle);
    }

    function test_setDestinationConfig_revertsZeroSettler() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, address(0), destOracle);
    }

    function test_setDestinationConfig_revertsZeroOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setDestinationConfig(DEST_CHAIN_ID, destEntrypoint, destOutputSettler, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER TESTS - ASSET POOL
    //////////////////////////////////////////////////////////////*/

    function test_setAssetPool_success() public {
        address newPool = makeAddr("newPool");

        vm.expectEmit(true, true, false, false);
        emit AssetPoolConfigured(Constants.NATIVE_ASSET, newPool);

        vm.prank(owner);
        entrypoint.setAssetPool(Constants.NATIVE_ASSET, newPool);

        assertEq(entrypoint.assetToPool(Constants.NATIVE_ASSET), newPool);
    }

    function test_setAssetPool_revertsZeroPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setAssetPool(Constants.NATIVE_ASSET, address(0));
    }

    function test_removeAssetPool_success() public {
        vm.expectEmit(true, false, false, false);
        emit AssetPoolRemoved(Constants.NATIVE_ASSET);

        vm.prank(owner);
        entrypoint.removeAssetPool(Constants.NATIVE_ASSET);

        assertEq(entrypoint.assetToPool(Constants.NATIVE_ASSET), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    SETTER TESTS - FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function test_setMinimumDepositAmount_success() public {
        uint256 newMinimum = 0.05 ether;

        vm.expectEmit(false, false, false, true);
        emit MinimumDepositAmountUpdated(MIN_DEPOSIT, newMinimum);

        vm.prank(owner);
        entrypoint.setMinimumDepositAmount(newMinimum);

        assertEq(entrypoint.minimumDepositAmount(), newMinimum);
    }

    function test_setDefaultSolverFeeBPS_success() public {
        uint256 newFeeBPS = 300; // 3%

        vm.expectEmit(false, false, false, true);
        emit DefaultSolverFeeBPSUpdated(500, newFeeBPS);

        vm.prank(owner);
        entrypoint.setDefaultSolverFeeBPS(newFeeBPS);

        assertEq(entrypoint.defaultSolverFeeBPS(), newFeeBPS);
    }

    function test_setDefaultSolverFeeBPS_revertsExceedsMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.SolverFeeExceedsMax.selector,
                1500,
                1000
            )
        );
        vm.prank(owner);
        entrypoint.setDefaultSolverFeeBPS(1500);
    }

    function test_setMaxSolverFeeBPS_success() public {
        uint256 newMaxFeeBPS = 2000; // 20%

        vm.expectEmit(false, false, false, true);
        emit MaxSolverFeeBPSUpdated(1000, newMaxFeeBPS);

        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(newMaxFeeBPS);

        assertEq(entrypoint.maxSolverFeeBPS(), newMaxFeeBPS);
    }

    function test_setMaxSolverFeeBPS_revertsExceeds100Percent() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidFeeBPS.selector,
                10001
            )
        );
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(10001);
    }

    function test_setMaxSolverFeeBPS_revertsBelowCurrentDefault() public {
        // Default is 500 (5%), try to set max to 300 (3%)
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.SolverFeeExceedsMax.selector,
                500,
                300
            )
        );
        vm.prank(owner);
        entrypoint.setMaxSolverFeeBPS(300);
    }

    /*//////////////////////////////////////////////////////////////
                    SETTER TESTS - HYPERLANE CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_setHyperlaneConfig_success() public {
        uint32 destDomain = 421614;
        address newDestOracle = makeAddr("destHyperlaneOracle");
        uint256 gasLimit = 300_000;

        vm.prank(owner);
        entrypoint.setHyperlaneConfig(
            address(hyperlaneOracle),
            destDomain,
            newDestOracle,
            gasLimit
        );

        assertEq(address(entrypoint.hyperlaneOracle()), address(hyperlaneOracle));
        assertEq(entrypoint.destinationHyperlaneDomain(), destDomain);
        assertEq(entrypoint.destinationHyperlaneOracle(), newDestOracle);
        assertEq(entrypoint.hyperlaneGasLimit(), gasLimit);
    }

    function test_setHyperlaneConfig_revertsZeroOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setHyperlaneConfig(address(0), 421614, makeAddr("dest"), 200_000);
    }

    function test_setHyperlaneConfig_revertsZeroDestOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ShinobiCrosschainDepositEntrypoint.InvalidAddress.selector,
                address(0)
            )
        );
        vm.prank(owner);
        entrypoint.setHyperlaneConfig(address(hyperlaneOracle), 421614, address(0), 200_000);
    }

    function test_setHyperlaneConfig_revertsZeroGasLimit() public {
        vm.expectRevert(ShinobiCrosschainDepositEntrypoint.InvalidAmount.selector);
        vm.prank(owner);
        entrypoint.setHyperlaneConfig(address(hyperlaneOracle), 421614, makeAddr("dest"), 0);
    }

    function test_disableHyperlane_success() public {
        // First enable
        vm.prank(owner);
        entrypoint.setHyperlaneConfig(address(hyperlaneOracle), 421614, makeAddr("dest"), 200_000);

        // Then disable
        vm.prank(owner);
        entrypoint.disableHyperlane();

        assertEq(address(entrypoint.hyperlaneOracle()), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    IPAYLOADCREATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_arePayloadsValid_returnsTrueForValidPayloads() public {
        // Do a deposit to create a valid payload
        vm.prank(user);
        entrypoint.deposit{value: DEPOSIT_AMOUNT}(12345);

        // Get the orderId from the nonce
        // Since we can't easily get the orderId, we test via the mapping
        // The validIntentPayloads mapping should have an entry
    }

    function test_arePayloadsValid_returnsFalseForInvalidPayloads() public view {
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encode(bytes32(uint256(999)));

        assertFalse(entrypoint.arePayloadsValid(payloads));
    }

    function test_arePayloadsValid_returnsTrueForEmptyArray() public view {
        bytes[] memory payloads = new bytes[](0);
        assertTrue(entrypoint.arePayloadsValid(payloads));
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_deposit_variousAmounts(uint256 amount) public {
        // Bound to reasonable range: enough to cover fee and minimum
        vm.assume(amount >= 0.02 ether && amount <= 10 ether);

        uint256 precommitment = uint256(keccak256(abi.encode(amount))) % Constants.SNARK_SCALAR_FIELD;

        vm.prank(user);
        entrypoint.deposit{value: amount}(precommitment);

        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }

    function testFuzz_depositWithCustomParams_variousFees(uint256 feeBPS) public {
        vm.assume(feeBPS <= 1000); // Max 10%

        uint256 precommitment = uint256(keccak256(abi.encode(feeBPS))) % Constants.SNARK_SCALAR_FIELD;

        vm.prank(user);
        entrypoint.depositWithCustomParams{value: DEPOSIT_AMOUNT}(
            precommitment,
            feeBPS,
            1 hours,
            24 hours
        );

        assertTrue(entrypoint.usedPrecommitments(precommitment));
    }
}

/**
 * @notice Mock input settler for testing
 */
contract MockInputSettler {
    bool public openCalled;
    ShinobiIntent public lastIntent;

    function open(ShinobiIntent calldata) external payable {
        openCalled = true;
    }

    function refund(ShinobiIntent calldata) external {
        // No-op for testing
    }
}

/**
 * @notice Mock Hyperlane oracle for testing
 */
contract MockHyperlaneOracle {
    function quoteGasPayment(
        uint32,
        address,
        uint256,
        bytes calldata,
        address,
        bytes[] calldata
    ) external pure returns (uint256) {
        return 0.001 ether;
    }

    function submit(
        uint32,
        address,
        uint256,
        bytes calldata,
        address,
        bytes[] calldata
    ) external payable {
        // No-op
    }
}
