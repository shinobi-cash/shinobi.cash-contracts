// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiOutputSettler} from "./interfaces/IShinobiOutputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title ShinobiWithdrawalOutputSettler
 * @author Karandeep Singh
 * @notice Output settler for cross-chain withdrawals on destination chain (user's chain)
 * @dev This contract handles fills for withdrawal intents on user's destination chain (e.g., Base Sepolia)
 *
 * @dev Flow: Arbitrum Sepolia (pool) → Base Sepolia (user)
 *      1. User creates withdrawal via ZK proof on Arbitrum Sepolia pool
 *      2. ShinobiCashEntrypoint validates ZK proof and creates intent
 *      3. Intent has NO intentOracle (ZK proof already validated user)
 *      4. Intent includes fillOracle for fill validation on origin chain
 *      5. Solver fills on Base Sepolia via this contract
 *      6. This contract validates intent uses configured fillOracle
 *      7. Performs OPTIMISTIC settlement (no oracle validation here)
 *      8. Simple ETH transfer to user recipient
 *      9. InputSettler on origin will validate fill via fillOracle
 *
 * @dev Security model:
 *      - Configured fillOracle prevents use of malicious/fake oracles
 *      - NO intentOracle validation (ZK proof provides authentication)
 *      - Optimistic settlement - assumes intent is valid
 *      - ZK proof on origin chain already validated withdrawer's credentials
 *      - ReentrancyGuard protects against reentrancy attacks
 *      - Fill records prevent double-filling same intent
 *      - Simpler and cheaper than deposit flow
 */
contract ShinobiWithdrawalOutputSettler is IShinobiOutputSettler, ReentrancyGuard, Ownable {
    using ShinobiIntentLib for ShinobiIntent;
    using MandateOutputEncodingLib for MandateOutput;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configured fill oracle that must be used for all withdrawals
     * @dev Set immutably in constructor for security
     * @dev All withdrawal intents must use this oracle, preventing oracle substitution attacks
     * @dev This oracle validates fills on origin chain (InputSettler validation)
     */
    address public immutable fillOracle;

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

    /// @notice Thrown when fillOracle address is zero in constructor
    error InvalidFillOracle();

    /// @notice Thrown when intent has no outputs
    error InvalidOutput();

    /// @notice Thrown when output chain doesn't match current chain
    error InvalidChain();

    /// @notice Thrown when fill deadline has passed
    error FillDeadlinePassed();

    /// @notice Thrown when intent uses wrong fillOracle (doesn't match configured)
    error FillOracleMismatch();

    /// @notice Thrown when output has already been filled
    error AlreadyFilled();

    /// @notice Thrown when output token is not native ETH
    error InvalidAsset();

    /// @notice Thrown when ETH transfer fails
    error ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the WithdrawalOutputSettler with immutable fillOracle
     * @dev FillOracle address is set once and cannot be changed (security feature)
     * @param _owner Address of the contract owner
     * @param _fillOracle Address of the fill oracle (validates fills on origin chain)
     */
    constructor(address _owner, address _fillOracle) Ownable(_owner) {
        if (_fillOracle == address(0)) revert InvalidFillOracle();
        fillOracle = _fillOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a withdrawal intent on user's chain (destination)
     * @dev OPTIMISTIC: Does NOT validate intent proof (ZK proof already validated on origin)
     * @dev Validates intent uses configured fillOracle for consistency
     * @dev Solver provides ETH and sends directly to recipient
     *
     * @param intent The withdrawal intent from pool chain (Arbitrum Sepolia), containing:
     *               - user: The ShinobiCashEntrypoint (not end user)
     *               - originChainId: Pool chain where ZK proof was validated
     *               - fillDeadline: Solver must fill before this timestamp
     *               - fillOracle: MUST match configured fillOracle
     *               - intentOracle: address(0) (no validation needed)
     *               - outputs: Array of outputs to fill (recipient gets ETH)
     *
     * @dev Process:
     *      1. Validate intent structure (has outputs, correct chain)
     *      2. Check fill deadline hasn't passed
     *      3. Validate intent uses configured fillOracle
     *      4. Fill each output (simple ETH transfer)
     *      5. NO intentOracle validation (optimistic settlement)
     *
     * @dev Requirements:
     *      - intent.outputs.length > 0
     *      - intent.outputs[0].chainId == block.chainid
     *      - block.timestamp <= intent.fillDeadline
     *      - intent.fillOracle == configured fillOracle (MANDATORY)
     *      - msg.value must match output amounts
     *      - Output not already filled
     *
     * @dev Why no intentOracle validation?
     *      - ZK proof on origin chain already validated the withdrawer
     *      - Privacy pool verified nullifier and commitment
     *      - Intent created by trusted ShinobiCashEntrypoint
     *      - No risk of spoofing since ZK proof cannot be faked
     *
     * @dev Why validate fillOracle?
     *      - Ensures InputSettler can validate fill with correct oracle
     *      - Prevents confusion from using wrong oracle address
     *      - Maintains consistency across the intent lifecycle
     */
    function fill(ShinobiIntent calldata intent) external payable override nonReentrant {
        // Validate intent has outputs
        if (intent.outputs.length == 0) revert InvalidOutput();

        // Validate this is the correct destination chain
        if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

        // Validate fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

        // CRITICAL: Validate intent uses the configured fillOracle
        // This ensures consistency - InputSettler will validate fill with this oracle
        if (intent.fillOracle != fillOracle) revert FillOracleMismatch();

        // Compute unique order identifier
        bytes32 orderId = intent.orderIdentifier();

        // NO intentOracle validation - optimistic settlement
        // ZK proof on origin chain already validated the withdrawer

        // Fill each output
        for (uint256 i = 0; i < intent.outputs.length; i++) {
            _fillOutput(orderId, intent.outputs[i], msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FILL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fill a single output by transferring ETH to recipient
     * @dev Stores fill record and performs simple ETH transfer
     *
     * @param orderId The unique order identifier
     * @param output The output to fill (contains recipient, amount)
     * @param solver The solver providing liquidity
     *
     * @dev Process:
     *      1. Validate output is for current chain
     *      2. Compute output hash
     *      3. Check output not already filled
     *      4. Store fill record
     *      5. Validate native ETH
     *      6. Transfer ETH to recipient (simple transfer, no callback)
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

        // For withdrawals, typically no callback needed - simple ETH transfer
        // User receives ETH directly on their destination chain
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

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
