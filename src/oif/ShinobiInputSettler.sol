// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "./interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "./libraries/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "./libraries/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @title ShinobiInputSettler
 * @author Karandeep Singh
 * @notice Unified input settler for Shinobi Cash cross-chain intents following OIF standard
 * @dev This contract handles the origin-side of cross-chain intents:
 *      - Escrows funds when an intent is created
 *      - Validates fill proofs from destination chain via oracle
 *      - Releases escrowed funds to solver after validation
 *      - Processes refunds for expired intents
 *
 * @dev Usage contexts:
 *      For withdrawals: origin = pool chain (e.g., Arbitrum Sepolia)
 *      For deposits: origin = user's chain (e.g., Base Sepolia)
 *
 * @dev Security model:
 *      - Only configured entrypoint can create intents (immutable)
 *      - Solver identity cryptographically bound via oracle attestation
 *      - Reentrancy protection via state checks
 *      - All native ETH transfers validated
 */
contract ShinobiInputSettler is IShinobiInputSettler {
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Address of the entrypoint contract (only caller allowed for open)
     * @dev For withdrawals: ShinobiCashEntrypoint
     * @dev For deposits: ShinobiCrosschainDepositEntrypoint
     * @dev Immutable for security - cannot be changed after deployment, preventing hijacking
     */
    address public immutable entrypoint;

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lifecycle states for intent orders
     * @dev None: Order doesn't exist or hasn't been created
     * @dev Deposited: Funds escrowed, awaiting fill or expiry
     * @dev Claimed: Solver filled and claimed escrowed funds
     * @dev Refunded: Intent expired and funds returned to user
     */
    enum OrderStatus {
        None,
        Deposited,
        Claimed,
        Refunded
    }

    /**
     * @notice Tracks the current state of each intent order
     * @dev Mapping: orderIdentifier => current status
     * @dev Used for state machine validation and reentrancy protection
     */
    mapping(bytes32 => OrderStatus) public orderStatus;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when entrypoint address is zero in constructor
    error InvalidEntrypoint();

    /// @notice Thrown when caller is not the configured entrypoint
    error UnauthorizedCaller();

    /// @notice Thrown when order is in wrong state for the operation
    error InvalidOrderStatus();

    /// @notice Thrown when intent origin chain doesn't match current chain
    error InvalidChain();

    /// @notice Thrown when input amount is zero or msg.value is insufficient
    error InvalidAmount();

    /// @notice Thrown when input asset is not native ETH (assetId != 0)
    error InvalidAsset();

    /// @notice Thrown when intent has no inputs or outputs
    error InvalidIntent();

    /// @notice Thrown when deadline has already passed
    error DeadlinePassed();

    /// @notice Thrown when expiry timestamp hasn't been reached yet
    error ExpiryNotReached();

    /// @notice Thrown when intent expires is before or equal to fillDeadline
    error InvalidDeadlineOrder();

    /// @notice Thrown when order state changed unexpectedly (reentrancy detected)
    error ReentrancyDetected();

    /// @notice Thrown when caller is not the solver who filled the order
    error NotOrderOwner();

    /// @notice Thrown when number of solve params doesn't match outputs
    error InvalidSolveParamsLength();

    /// @notice Thrown when multiple different solvers attempt to fill same intent
    error MultipleSolversNotSupported();

    /// @notice Thrown when output was filled after the fill deadline
    /// @param deadline The fill deadline timestamp
    /// @param filledAt The actual fill timestamp
    error FilledTooLate(uint32 deadline, uint32 filledAt);

    /// @notice Thrown when ETH transfer fails during finalize or refund
    error ETHTransferFailed();

    /// @notice Thrown when refund calldata length is invalid (too short for abi.decode)
    error InvalidRefundCalldataLength();

    /// @notice Thrown when refund target address is zero
    error InvalidRefundTarget();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the ShinobiInputSettler with immutable entrypoint
     * @dev Entrypoint address is set once and cannot be changed (security feature)
     * @param _entrypoint Address of the entrypoint contract
     */
    constructor(address _entrypoint) {
        if (_entrypoint == address(0)) revert InvalidEntrypoint();
        entrypoint = _entrypoint;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new intent and escrow funds on origin chain
     * @dev CRITICAL: Only the configured entrypoint can call this function
     * @dev The entrypoint is responsible for constructing the intent with verified user context
     * @dev Follows checks-effects-interactions pattern with reentrancy guard
     *
     * @param intent The intent to open, containing:
     *               - user: The originator of the intent
     *               - nonce: Unique identifier component
     *               - originChainId: Must match current chain
     *               - fillDeadline: Solver must fill before this timestamp
     *               - expires: After this timestamp, funds can be refunded
     *               - fillOracle: Oracle to validate fills
     *               - inputs: Array of [assetId, amount] (only native ETH supported)
     *               - outputs: Destination chain outputs
     *               - intentOracle: Oracle for intent validation (if needed)
     *               - refundCalldata: Custom refund logic (optional)
     *
     * @dev Requirements:
     *      - msg.sender must be entrypoint
     *      - intent.originChainId must match block.chainid
     *      - Deadlines must be valid (now < fillDeadline < expires)
     *      - Must have at least one input and output
     *      - msg.value must match total input amount
     *      - Only native ETH (assetId = 0) supported
     */
    function open(ShinobiIntent calldata intent) external payable override {
        // CRITICAL: Only entrypoint can create intents
        if (msg.sender != entrypoint) revert UnauthorizedCaller();

        // Validate intent structure and deadlines
        _validateIntent(intent);

        // Compute unique order identifier
        bytes32 orderId = orderIdentifier(intent);

        // Ensure order doesn't already exist
        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();

        // Mark as deposited BEFORE collecting funds (reentrancy protection)
        orderStatus[orderId] = OrderStatus.Deposited;

        // Collect and validate native ETH inputs
        _collectInputs(intent.inputs);

        // Verify state hasn't changed (reentrancy guard)
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        // ETH is now safely escrowed in this contract
        emit Open(orderId, intent);
    }

    /**
     * @notice Finalize intent after solver fills outputs on destination chain
     * @dev Implements standard OIF settlement pattern with cryptographic solver binding
     * @dev Can only be called by the solver who filled the outputs (verified via oracle)
     *
     * @param intent The original intent that was opened
     * @param solveParams Array of solve parameters (one per output), containing:
     *                    - solver: Address of the solver (bytes32)
     *                    - timestamp: When the output was filled (uint32)
     * @param destination Where to send the escrowed funds (typically solver's address)
     *
     * @dev Process:
     *      1. Verify order is in Deposited state
     *      2. Check fill deadline hasn't passed
     *      3. Extract solver address from solveParams
     *      4. Verify all outputs filled by same solver
     *      5. Verify caller is the solver
     *      6. Validate fills via oracle attestation
     *      7. Mark as Claimed
     *      8. Transfer escrowed ETH to destination
     *
     * @dev Requirements:
     *      - Order must be in Deposited state
     *      - Current time must be <= fillDeadline
     *      - solveParams length must match outputs length
     *      - All outputs must be filled by same solver
     *      - Caller must be the solver
     *      - Oracle must attest to valid fills
     */
    function finalise(
        ShinobiIntent calldata intent,
        IShinobiInputSettler.SolveParams[] calldata solveParams,
        bytes32 destination
    ) external {
        bytes32 orderId = orderIdentifier(intent);

        // Verify order is in correct state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Check fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert DeadlinePassed();

        // SECURITY: Extract solver address from first solve param (validated by oracle)
        bytes32 solver = solveParams[0].solver;

        // SECURITY: Shinobi currently requires single solver for all outputs
        // Validate all outputs were filled by the same solver
        for (uint256 i = 1; i < solveParams.length; i++) {
            if (solveParams[i].solver != solver) revert MultipleSolversNotSupported();
        }

        // SECURITY: Verify caller is actually the solver who filled the outputs
        _orderOwnerIsCaller(solver);

        // CRITICAL: Validate fills via oracle
        // This cryptographically binds the solver address to the fill events
        _validateFills(intent, orderId, solveParams);

        // Update state to Claimed
        orderStatus[orderId] = OrderStatus.Claimed;

        // Calculate total escrowed amount
        uint256 amount = _calculateTotalAmount(intent.inputs);

        // Transfer escrowed ETH to destination
        address destinationAddress = _bytes32ToAddress(destination);
        (bool success,) = destinationAddress.call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Finalised(orderId, solver, destination);
    }

    /**
     * @notice Refund an expired intent back to the original user
     * @dev Can be called by anyone after intent expires (permissionless)
     * @dev Funds are ALWAYS sent to intent.user, never to caller (security feature)
     *
     * @param intent The original intent to refund
     *
     * @dev Process:
     *      1. Verify order is in Deposited state
     *      2. Check expiry timestamp has passed
     *      3. Mark as Refunded
     *      4. Execute refund (simple ETH transfer or custom calldata)
     *
     * @dev Refund modes:
     *      - If intent.refundCalldata is empty: Direct ETH transfer to intent.user
     *      - Otherwise: Execute custom refund logic (e.g., return to privacy pool)
     *
     * @dev Requirements:
     *      - Order must be in Deposited state
     *      - Current time must be > expires
     *      - ETH transfer must succeed
     */
    function refund(ShinobiIntent calldata intent) external override {
        bytes32 orderId = orderIdentifier(intent);

        // Verify order is in correct state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Check expiry has passed
        if (block.timestamp <= intent.expires) revert ExpiryNotReached();

        // Update state to Refunded
        orderStatus[orderId] = OrderStatus.Refunded;

        // Calculate total escrowed amount
        uint256 totalAmount = _calculateTotalAmount(intent.inputs);

        if (intent.refundCalldata.length == 0) {
            // Simple refund: Direct ETH transfer to user
            (bool success,) = intent.user.call{value: totalAmount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            // Custom refund: Execute calldata (e.g., handleRefund on entrypoint)
            // SECURITY: Validate calldata length before decoding to prevent out-of-bounds reads
            // Minimum length: 32 bytes for address + 32 bytes for dynamic array offset = 64 bytes
            if (intent.refundCalldata.length < 64) revert InvalidRefundCalldataLength();

            (address target, bytes memory functionCalldata) =
                abi.decode(intent.refundCalldata, (address, bytes));

            // SECURITY: Ensure refund target is not zero address
            if (target == address(0)) revert InvalidRefundTarget();

            (bool success,) = target.call{value: totalAmount}(functionCalldata);
            if (!success) revert ETHTransferFailed();
        }

        emit Refunded(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate intent structure and parameters
     * @dev Performs comprehensive validation of intent before accepting
     * @param intent The intent to validate
     */
    function _validateIntent(ShinobiIntent calldata intent) internal view {
        // Verify this is the correct origin chain
        if (intent.originChainId != block.chainid) revert InvalidChain();

        // Validate deadlines haven't passed
        if (block.timestamp >= intent.fillDeadline) revert DeadlinePassed();
        if (block.timestamp >= intent.expires) revert DeadlinePassed();

        // Validate deadline ordering (expires must be after fillDeadline)
        if (intent.expires <= intent.fillDeadline) revert InvalidDeadlineOrder();

        // Ensure intent has at least one input
        if (intent.inputs.length == 0) revert InvalidIntent();

        // Ensure intent has at least one output
        if (intent.outputs.length == 0) revert InvalidIntent();
    }

    /**
     * @notice Collect and validate native ETH inputs
     * @dev Verifies msg.value matches expected amount and only native ETH is used
     * @param inputs Array of [assetId, amount] tuples
     */
    function _collectInputs(uint256[2][] calldata inputs) internal {
        if (inputs.length == 0) revert InvalidAmount();

        uint256 expectedEthValue = 0;

        for (uint256 i = 0; i < inputs.length; i++) {
            uint256 assetId = inputs[i][0];
            uint256 amount = inputs[i][1];

            // Only native ETH (assetId = 0) is supported
            if (assetId != 0) revert InvalidAsset();

            expectedEthValue += amount;
        }

        // Verify caller sent sufficient ETH
        if (msg.value < expectedEthValue) revert InvalidAmount();

        // ETH is now escrowed in this contract
    }

    /**
     * @notice Validate fills via oracle attestation (STANDARD OIF PATTERN)
     * @dev Builds proof series that cryptographically binds solver to fill events
     * @dev Oracle must attest that solver filled each output at specified timestamps
     *
     * @param intent The intent being finalized
     * @param orderId The computed order identifier
     * @param solveParams Array of solve parameters (solver, timestamp) for each output
     *
     * @dev Proof structure for each output (128 bytes total):
     *      - bytes32: remoteChainId (where output was filled)
     *      - bytes32: remoteOracle (oracle on remote chain)
     *      - bytes32: remoteSettler (settler on remote chain)
     *      - bytes32: payloadHash = keccak256(solver | orderId | timestamp | output)
     */
    function _validateFills(
        ShinobiIntent calldata intent,
        bytes32 orderId,
        IShinobiInputSettler.SolveParams[] calldata solveParams
    ) internal view {
        uint256 numOutputs = intent.outputs.length;

        // Validate we have solve params for each output
        if (solveParams.length != numOutputs) revert InvalidSolveParamsLength();

        // Build proof series for oracle validation (128 bytes per output)
        bytes memory proofSeries = new bytes(128 * numOutputs);

        for (uint256 i = 0; i < numOutputs; i++) {
            uint32 outputFilledAt = solveParams[i].timestamp;

            // Validate output was filled before deadline
            if (intent.fillDeadline < outputFilledAt) {
                revert FilledTooLate(intent.fillDeadline, outputFilledAt);
            }

            // Reconstruct output structure for encoding
            MandateOutput memory output = MandateOutput({
                chainId: intent.outputs[i].chainId,
                oracle: intent.outputs[i].oracle,
                settler: intent.outputs[i].settler,
                token: intent.outputs[i].token,
                amount: intent.outputs[i].amount,
                recipient: intent.outputs[i].recipient,
                call: intent.outputs[i].call,
                context: intent.outputs[i].context
            });

            // Build payload hash that binds solver to this specific fill
            // payloadHash = keccak256(solver | orderId | timestamp | output)
            bytes32 payloadHash = keccak256(
                MandateOutputEncodingLib.encodeFillDescriptionMemory(
                    solveParams[i].solver, orderId, outputFilledAt, output
                )
            );

            // Extract remote chain parameters
            bytes32 remoteChainId = bytes32(output.chainId);
            bytes32 remoteOracle = output.oracle;
            bytes32 remoteSettler = output.settler;

            // Pack into proof series: [chainId, oracle, settler, payloadHash]
            assembly {
                let offset := add(proofSeries, add(32, mul(i, 128)))
                mstore(offset, remoteChainId)
                mstore(add(offset, 32), remoteOracle)
                mstore(add(offset, 64), remoteSettler)
                mstore(add(offset, 96), payloadHash)
            }
        }

        // CRITICAL: Validate via fill oracle
        // Oracle must attest that each output was filled by the specified solver
        IInputOracle(intent.fillOracle).efficientRequireProven(proofSeries);
    }

    /**
     * @notice Validate that caller is the order owner/solver
     * @dev Only reads rightmost 20 bytes to extract address
     * @param orderOwner The solver address (left-padded bytes32)
     */
    function _orderOwnerIsCaller(bytes32 orderOwner) internal view {
        if (_bytes32ToAddress(orderOwner) != msg.sender) revert NotOrderOwner();
    }

    /**
     * @notice Calculate total amount from input array
     * @param inputs Array of [assetId, amount] tuples
     * @return totalAmount Sum of all input amounts
     */
    function _calculateTotalAmount(uint256[2][] calldata inputs)
        internal
        pure
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < inputs.length; i++) {
            totalAmount += inputs[i][1];
        }
    }

    /**
     * @notice Convert bytes32 to address (standard OIF helper)
     * @dev Extracts rightmost 20 bytes as address
     * @param b The bytes32 value (left-padded address)
     * @return addr The extracted address
     */
    function _bytes32ToAddress(bytes32 b) internal pure returns (address addr) {
        assembly {
            addr := b
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Compute unique identifier for an intent
     * @dev Uses ShinobiIntentLib to compute deterministic order ID
     * @param intent The intent to compute ID for
     * @return The unique order identifier (bytes32)
     */
    function orderIdentifier(ShinobiIntent memory intent) public pure override returns (bytes32) {
        return intent.orderIdentifier();
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH
     * @dev Required for refund and finalize operations
     */
    receive() external payable {}
}
