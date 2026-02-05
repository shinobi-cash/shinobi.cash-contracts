// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {BaseShinobiOutputSettler} from "./BaseShinobiOutputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";

/**
 * @title ShinobiDepositOutputSettler
 * @author Karandeep Singh
 * @notice Output settler for cross-chain deposits on destination chain (pool chain)
 * @dev This contract handles fills for deposit intents on the pool chain (e.g., Arbitrum Sepolia)
 *
 * @dev Flow: Base Sepolia (user) → Arbitrum Sepolia (pool)
 *      1. User creates deposit intent on Base Sepolia via ShinobiCrosschainDepositEntrypoint
 *      2. DepositEntrypoint submits intent proof to HyperlaneOracle on origin
 *      3. Hyperlane relays proof to HyperlaneOracle on destination (this chain)
 *      4. Solver fills on Arbitrum Sepolia via this contract
 *      5. This contract VALIDATES intent proof via intentOracle (MANDATORY)
 *      6. Uses origin chain config to query isProven() with correct parameters
 *      7. Calls crosschainDeposit() on pool entrypoint with verified depositor
 *
 * @dev Security model:
 *      - Configured intentOracle prevents use of malicious/fake oracles
 *      - Origin chain config provides correct oracle/app addresses for isProven()
 *      - MANDATORY intentOracle validation prevents depositor spoofing
 *      - Without oracle validation, attacker could create fake deposit intent
 *      - Oracle cryptographically proves intent came from legitimate user
 *      - ReentrancyGuard protects against reentrancy attacks
 *      - Fill records prevent double-filling same intent
 */
contract ShinobiDepositOutputSettler is BaseShinobiOutputSettler {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configured intent oracle that must be used for all deposits
     * @dev Set immutably in constructor for security
     * @dev This is the HyperlaneOracle on THIS chain (destination)
     * @dev All deposit intents must use this oracle, preventing oracle substitution attacks
     */
    address public immutable intentOracle;

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration for each supported origin chain
     * @dev Maps origin chainId to oracle/app addresses on that chain
     */
    struct OriginChainConfig {
        address hyperlaneOracle;     // HyperlaneOracle address on origin chain
        address depositEntrypoint;   // DepositEntrypoint address on origin chain
        bool isConfigured;           // Whether this origin chain is supported
    }

    /**
     * @notice Origin chain configurations
     * @dev Mapping: originChainId => config
     */
    mapping(uint256 => OriginChainConfig) public originChainConfigs;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an origin chain config is set
    event OriginChainConfigSet(
        uint256 indexed chainId,
        address indexed hyperlaneOracle,
        address indexed depositEntrypoint
    );

    /// @notice Emitted when an origin chain config is removed
    event OriginChainConfigRemoved(uint256 indexed chainId);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when intentOracle address is zero in constructor
    error InvalidIntentOracle();

    /// @notice Thrown when intent uses wrong intentOracle (doesn't match configured)
    error IntentOracleMismatch();

    /// @notice Thrown when intent proof validation fails
    error IntentNotProven();

    /// @notice Thrown when deposit output has no callback data (deposits require callback)
    error EmptyCallbackData();

    /// @notice Thrown when callback execution fails
    error CallbackFailed();

    /// @notice Thrown when origin chain is not configured
    error OriginChainNotConfigured(uint256 chainId);

    /// @notice Thrown when setting config with zero address
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the DepositOutputSettler with immutable intentOracle
     * @dev IntentOracle is the HyperlaneOracle on THIS chain (destination)
     * @param _owner Address of the contract owner
     * @param _intentOracle Address of the intent oracle (HyperlaneOracle on this chain)
     */
    constructor(address _owner, address _intentOracle) BaseShinobiOutputSettler(_owner) {
        if (_intentOracle == address(0)) revert InvalidIntentOracle();
        intentOracle = _intentOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set configuration for an origin chain
     * @dev Required before accepting deposits from a new origin chain
     * @param _chainId The origin chain ID
     * @param _hyperlaneOracle HyperlaneOracle address on the origin chain
     * @param _depositEntrypoint DepositEntrypoint address on the origin chain
     */
    function setOriginChainConfig(
        uint256 _chainId,
        address _hyperlaneOracle,
        address _depositEntrypoint
    ) external onlyOwner {
        if (_hyperlaneOracle == address(0)) revert InvalidAddress();
        if (_depositEntrypoint == address(0)) revert InvalidAddress();

        originChainConfigs[_chainId] = OriginChainConfig({
            hyperlaneOracle: _hyperlaneOracle,
            depositEntrypoint: _depositEntrypoint,
            isConfigured: true
        });

        emit OriginChainConfigSet(_chainId, _hyperlaneOracle, _depositEntrypoint);
    }

    /**
     * @notice Remove configuration for an origin chain
     * @dev Disables deposits from the specified origin chain
     * @param _chainId The origin chain ID to remove
     */
    function removeOriginChainConfig(uint256 _chainId) external onlyOwner {
        delete originChainConfigs[_chainId];
        emit OriginChainConfigRemoved(_chainId);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a deposit intent on pool chain (destination)
     * @dev CRITICAL: Always validates intent proof via configured intentOracle
     * @dev Solver provides ETH and calls crosschainDeposit with verified depositor
     *
     * @param intent The deposit intent from origin chain (Base Sepolia), containing:
     *               - user: The verified depositor address
     *               - originChainId: Origin chain where intent was created
     *               - fillDeadline: Solver must fill before this timestamp
     *               - intentOracle: MUST match configured intentOracle
     *               - outputs: Array of outputs to fill
     *
     * @dev Process:
     *      1. Validate intent structure (has outputs, correct chain)
     *      2. Check fill deadline hasn't passed
     *      3. CRITICAL: Validate intent uses configured intentOracle
     *      4. CRITICAL: Validate origin chain is configured
     *      5. CRITICAL: Validate intent proof via oracle with correct parameters
     *      6. Fill each output (execute callback)
     *
     * @dev Requirements:
     *      - intent.outputs.length == 1 (deposits have exactly one output)
     *      - intent.outputs[0].chainId == block.chainid
     *      - block.timestamp <= intent.fillDeadline
     *      - intent.intentOracle == configured intentOracle (MANDATORY)
     *      - Origin chain must be configured
     *      - Oracle must attest to valid intent
     *      - msg.value must match output amounts
     *      - Output not already filled
     */
    function fill(ShinobiIntent calldata intent) external payable override nonReentrant {
        // SECURITY: Deposits must have exactly one output
        // This prevents complex multi-output attacks and ensures clean accounting
        if (intent.outputs.length != 1) revert InvalidOutput();

        // Validate this is the correct destination chain
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

        // Validate fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

        // CRITICAL: Validate intent uses the configured intentOracle
        // This prevents oracle substitution attacks where attacker uses malicious oracle
        if (intent.intentOracle != intentOracle) revert IntentOracleMismatch();

        // CRITICAL: Get origin chain config for correct isProven() parameters
        OriginChainConfig memory originConfig = originChainConfigs[intent.originChainId];
        if (!originConfig.isConfigured) revert OriginChainNotConfigured(intent.originChainId);

        // Compute unique order identifier
        bytes32 orderId = intent.orderIdentifier();

        // CRITICAL: Validate intent proof via configured oracle
        // Query parameters:
        // - remoteChainId: Origin chain where intent was created
        // - remoteOracle: HyperlaneOracle on origin chain (sent the message)
        // - application: DepositEntrypoint on origin chain (created the payload)
        // - dataHash: keccak256(abi.encode(orderId)) - the hashed payload
        if (
            !IInputOracle(intentOracle).isProven(
                intent.originChainId,
                bytes32(uint256(uint160(originConfig.hyperlaneOracle))),
                bytes32(uint256(uint160(originConfig.depositEntrypoint))),
                keccak256(abi.encode(orderId))
            )
        ) {
            revert IntentNotProven();
        }

        // Fill the single deposit output
        _fillOutput(orderId, intent.outputs[0], msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a single output by transferring ETH and executing callback
     * @dev Stores fill record and executes crosschainDeposit callback
     *
     * @param orderId The unique order identifier
     * @param output The output to fill (contains recipient, amount, callback)
     * @param solver The solver providing liquidity
     *
     * @dev Process:
     *      1. Validate output is for current chain
     *      2. Create and store fill record (includes IPayloadCreator validation data)
     *      3. Validate native ETH
     *      4. Execute callback (crosschainDeposit)
     */
    function _fillOutput(bytes32 orderId, MandateOutput calldata output, address solver) internal {
        // Validate output (chain and asset)
        _validateOutput(output);

        // Create and store fill record (checks for duplicates, stores fill payload hash)
        _createAndStoreFillRecord(orderId, output, solver);

        // Extract recipient and amount
        address recipient = address(uint160(uint256(output.recipient)));
        uint256 amount = output.amount;

        // SECURITY: Deposits MUST have callback data (crosschainDeposit call)
        // Without callback, deposit cannot be processed into privacy pool
        if (output.call.length == 0) revert EmptyCallbackData();

        // For deposits, output.call contains crosschainDeposit(depositor, amount, precommitment)
        // Execute callback with ETH payment
        (bool success,) = recipient.call{value: amount}(output.call);
        if (!success) revert CallbackFailed();

        emit OutputFilled(
            orderId, bytes32(uint256(uint160(solver))), uint32(block.timestamp), output, amount
        );
    }
}
