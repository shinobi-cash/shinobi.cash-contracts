// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "../interfaces/IShinobiOutputSettler.sol";
import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../lib/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title ShinobiDepositOutputSettler
 * @author Karandeep Singh
 * @notice Output settler for cross-chain deposits on destination chain (pool chain)
 * @dev This contract handles fills for deposit intents on the pool chain (e.g., Arbitrum Sepolia)
 *
 * @dev Flow: Base Sepolia (user) → Arbitrum Sepolia (pool)
 *      1. User creates deposit intent on Base Sepolia via ShinobiCrosschainDepositEntrypoint
 *      2. Intent includes intentOracle for validation
 *      3. Solver fills on Arbitrum Sepolia via this contract
 *      4. This contract VALIDATES intent proof via intentOracle (MANDATORY)
 *      5. Validates intent uses the configured intentOracle (security)
 *      6. Calls processCrossChainDeposit() on pool entrypoint with verified depositor
 *
 * @dev Security model:
 *      - Configured intentOracle prevents use of malicious/fake oracles
 *      - MANDATORY intentOracle validation prevents depositor spoofing
 *      - Without oracle validation, attacker could create fake deposit intent
 *      - Oracle cryptographically proves intent came from legitimate user
 *      - ReentrancyGuard protects against reentrancy attacks
 *      - Fill records prevent double-filling same intent
 */
contract ShinobiDepositOutputSettler is IShinobiOutputSettler, ReentrancyGuard, Ownable {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configured intent oracle that must be used for all deposits
     * @dev Set immutably in constructor for security
     * @dev All deposit intents must use this oracle, preventing oracle substitution attacks
     */
    address public immutable intentOracle;

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tracks which outputs have been filled
     * @dev Mapping: orderId => outputHash => fillRecordHash
     * @dev fillRecordHash = keccak256(solver, timestamp)
     * @dev Prevents double-filling and enables fill verification
     */
    mapping(bytes32 => mapping(bytes32 => bytes32)) internal _fillRecords;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when intentOracle address is zero in constructor
    error InvalidIntentOracle();

    /// @notice Thrown when intent has no outputs
    error InvalidOutput();

    /// @notice Thrown when output chain doesn't match current chain
    error InvalidChain();

    /// @notice Thrown when fill deadline has passed
    error FillDeadlinePassed();

    /// @notice Thrown when intent uses wrong intentOracle (doesn't match configured)
    error IntentOracleMismatch();

    /// @notice Thrown when intent proof validation fails
    error IntentNotProven();

    /// @notice Thrown when output has already been filled
    error AlreadyFilled();

    /// @notice Thrown when output token is not native ETH
    error InvalidAsset();

    /// @notice Thrown when callback execution fails
    error CallbackFailed();

    /// @notice Thrown when ETH transfer fails
    error ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the DepositOutputSettler with immutable intentOracle
     * @dev IntentOracle address is set once and cannot be changed (security feature)
     * @param _owner Address of the contract owner
     * @param _intentOracle Address of the intent oracle (validates deposit intents)
     */
    constructor(address _owner, address _intentOracle) Ownable(_owner) {
        if (_intentOracle == address(0)) revert InvalidIntentOracle();
        intentOracle = _intentOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a deposit intent on pool chain (destination)
     * @dev CRITICAL: Always validates intent proof via configured intentOracle
     * @dev Solver provides ETH and calls processCrossChainDeposit with verified depositor
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
     *      4. CRITICAL: Validate intent proof via oracle
     *      5. Fill each output (execute callback)
     *
     * @dev Requirements:
     *      - intent.outputs.length > 0
     *      - intent.outputs[0].chainId == block.chainid
     *      - block.timestamp <= intent.fillDeadline
     *      - intent.intentOracle == configured intentOracle (MANDATORY)
     *      - Oracle must attest to valid intent
     *      - msg.value must match output amounts
     *      - Output not already filled
     */
    function fill(ShinobiIntent calldata intent) external payable override nonReentrant {
        // Validate intent has outputs
        if (intent.outputs.length == 0) revert InvalidOutput();

        // Validate this is the correct destination chain
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

        // Validate fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

        // CRITICAL: Validate intent uses the configured intentOracle
        // This prevents oracle substitution attacks where attacker uses malicious oracle
        if (intent.intentOracle != intentOracle) revert IntentOracleMismatch();

        // Compute unique order identifier
        bytes32 orderId = intent.orderIdentifier();

        // CRITICAL: Validate intent proof via configured oracle
        // Oracle must attest that this intent was legitimately created on origin chain
        // Params: (originChainId, oracleOnOrigin, settlerOnDestination, orderId)
        if (
            !IInputOracle(intentOracle).isProven(
                intent.originChainId,
                bytes32(uint256(uint160(intentOracle))),
                bytes32(uint256(uint160(address(this)))),
                orderId
            )
        ) {
            revert IntentNotProven();
        }

        // Fill each output (typically just one for deposits)
        for (uint256 i = 0; i < intent.outputs.length; i++) {
            _fillOutput(orderId, intent.outputs[i], msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a single output by transferring ETH and executing callback
     * @dev Stores fill record and executes processCrossChainDeposit callback
     *
     * @param orderId The unique order identifier
     * @param output The output to fill (contains recipient, amount, callback)
     * @param solver The solver providing liquidity
     *
     * @dev Process:
     *      1. Validate output is for current chain
     *      2. Compute output hash
     *      3. Check output not already filled
     *      4. Store fill record
     *      5. Validate native ETH
     *      6. Execute callback (processCrossChainDeposit)
     */
    function _fillOutput(bytes32 orderId, MandateOutput calldata output, address solver) internal {
        // Validate output is for this chain
        if (output.chainId != block.chainid) revert InvalidChain();

        // Compute output hash for fill tracking
        bytes32 outputHash = output.getMandateOutputHash();

        // Check if already filled
        bytes32 existingFillRecord = _fillRecords[orderId][outputHash];
        if (existingFillRecord != bytes32(0)) revert AlreadyFilled();

        // Create fill record: keccak256(solver, timestamp)
        bytes32 fillRecordHash =
            keccak256(abi.encodePacked(bytes32(uint256(uint160(solver))), uint32(block.timestamp)));

        // Store fill record BEFORE external call (CEI pattern)
        _fillRecords[orderId][outputHash] = fillRecordHash;

        // Extract recipient and amount
        address recipient = address(uint160(uint256(output.recipient)));
        uint256 amount = output.amount;

        // Validate token is native ETH (only supported asset)
        if (output.token != bytes32(0)) revert InvalidAsset();

        // For deposits, output.call contains processCrossChainDeposit(depositor, amount, precommitment)
        // Execute callback with ETH payment
        if (output.call.length > 0) {
            (bool success,) = recipient.call{value: amount}(output.call);
            if (!success) revert CallbackFailed();
        } else {
            // Fallback: Simple ETH transfer (should not happen for deposits)
            (bool success,) = payable(recipient).call{value: amount}("");
            if (!success) revert ETHTransferFailed();
        }

        emit OutputFilled(
            orderId, bytes32(uint256(uint160(solver))), uint32(block.timestamp), output, amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get fill record for a specific output
     * @dev Returns fillRecordHash = keccak256(solver, timestamp) or bytes32(0) if not filled
     * @param orderId The order identifier
     * @param outputHash The output hash
     * @return payloadHash The fill record hash
     */
    function getFillRecord(bytes32 orderId, bytes32 outputHash)
        external
        view
        override
        returns (bytes32 payloadHash)
    {
        return _fillRecords[orderId][outputHash];
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH
     * @dev Required for solver to provide liquidity
     */
    receive() external payable {}
}
