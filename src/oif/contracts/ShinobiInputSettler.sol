// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {IShinobiInputSettler} from "../interfaces/IShinobiInputSettler.sol";
import {ShinobiIntent} from "../types/ShinobiIntentType.sol";
import {ShinobiIntentLib} from "../lib/ShinobiIntentLib.sol";
import {IInputOracle} from "oif-contracts/interfaces/IInputOracle.sol";
import {MandateOutputEncodingLib} from "oif-contracts/libs/MandateOutputEncodingLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @title ShinobiInputSettler
 * @notice Unified input settler following standard OIF security model
 * @dev Uses SolveParams for solver tracking and validation (same as InputSettlerEscrow)
 * @dev Handles intent creation on origin chain (where funds originate)
 * @dev For withdrawals: origin = pool chain (Ethereum)
 * @dev For deposits: origin = user's chain (e.g., Arbitrum)
 * @dev Escrows funds and releases to solver after fill proof validation
 */
contract ShinobiInputSettler is IShinobiInputSettler {
    using ShinobiIntentLib for ShinobiIntent;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Order status enum
    enum OrderStatus {
        None,
        Deposited,
        Claimed,
        Refunded
    }

    /// @notice Mapping from order ID to order status
    mapping(bytes32 => OrderStatus) public orderStatus;

    /// @notice Address of the entrypoint (only caller allowed for open)
    /// @dev For withdrawals: ShinobiCashEntrypoint
    /// @dev For deposits: ShinobiCrosschainDepositEntrypoint
    address public entrypoint;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidOrderStatus();
    error InvalidAmount();
    error InvalidChain();
    error TimestampPassed();
    error TimestampNotPassed();
    error RefundExecutionFailed();
    error UnauthorizedCaller();
    error ReentrancyDetected();
    error InvalidAsset();
    error NotOrderOwner();
    error FilledTooLate(uint32 expected, uint32 actual);
    error InvalidSolveParamsLength();
    error MultipleSolversNotSupported();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open an intent and escrow funds
     * @dev CRITICAL: Can only be called by configured entrypoint
     * @dev The entrypoint constructs the intent with verified user context
     * @param intent The intent from the entrypoint
     */
    function open(ShinobiIntent calldata intent) external payable override {
        // CRITICAL: Only entrypoint can call this
        if (msg.sender != entrypoint) revert UnauthorizedCaller();

        // Validate intent structure
        _validateIntent(intent);

        bytes32 orderId = orderIdentifier(intent);

        // Check order doesn't exist
        if (orderStatus[orderId] != OrderStatus.None) revert InvalidOrderStatus();

        // Mark as deposited BEFORE collecting funds (reentrancy protection)
        orderStatus[orderId] = OrderStatus.Deposited;

        // Collect and validate native ETH inputs
        _collectInputs(intent.inputs);

        // Validate no reentrancy
        if (orderStatus[orderId] != OrderStatus.Deposited) revert ReentrancyDetected();

        // ETH is now escrowed in this contract
        emit Open(orderId, intent);
    }

    /**
     * @notice Finalize intent after solver fills on destination (STANDARD OIF PATTERN)
     * @dev Validates solver identity and fill proofs via oracle, then releases escrowed ETH
     * @dev Uses same security model as InputSettlerEscrow with SolveParams
     * @param intent The original intent
     * @param solveParams Array of solve parameters (one per output)
     * @param destination Where to send the funds (typically solver's address)
     */
    function finalise(
        ShinobiIntent calldata intent,
        IShinobiInputSettler.SolveParams[] calldata solveParams,
        bytes32 destination
    ) external {
        bytes32 orderId = orderIdentifier(intent);

        // Check order is in deposited state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Validate fill deadline hasn't passed
        if (block.timestamp > intent.fillDeadline) revert TimestampPassed();

        // SECURITY: Get the solver from solveParams (validated by oracle)
        bytes32 solver = solveParams[0].solver;

        // SECURITY: Validate all outputs filled by same solver
        // Shinobi currently supports single solver for all outputs
        for (uint256 i = 1; i < solveParams.length; i++) {
            if (solveParams[i].solver != solver) revert MultipleSolversNotSupported();
        }

        // SECURITY: Verify caller is the actual solver who filled the order
        _orderOwnerIsCaller(solver);

        // Validate fills via oracle (binds solver address to fills cryptographically)
        _validateFills(intent, orderId, solveParams);

        // Mark as claimed
        orderStatus[orderId] = OrderStatus.Claimed;

        // Release escrowed ETH to destination (handles multiple inputs correctly)
        uint256 amount = _calculateTotalAmount(intent.inputs);
        address destinationAddress = _bytes32ToAddress(destination);
        (bool success, ) = destinationAddress.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Finalised(orderId, solver, destination);
    }


    /**
     * @notice Refund expired intent
     * @dev Can be called by anyone after intent expiry
     * @dev Funds are always sent to intent.user, not the caller
     * @param intent The original intent
     */
    function refund(
        ShinobiIntent calldata intent
    ) external override {
        bytes32 orderId = orderIdentifier(intent);

        // Check order is in deposited state
        if (orderStatus[orderId] != OrderStatus.Deposited) revert InvalidOrderStatus();

        // Validate expiry has passed
        if (block.timestamp <= intent.expires) revert TimestampNotPassed();

        // Mark as refunded (intent validated via orderIdentifier match)
        orderStatus[orderId] = OrderStatus.Refunded;

        uint256 totalAmount = _calculateTotalAmount(intent.inputs);

        if (intent.refundCalldata.length == 0) {
            // Simple refund: transfer ETH back to user
            (bool success, ) = intent.user.call{value: totalAmount}("");
            if (!success) revert RefundExecutionFailed();
        } else {
            // Custom refund: execute calldata
            (address target, bytes memory functionCalldata) = abi.decode(
                intent.refundCalldata,
                (address, bytes)
            );

            (bool success, ) = target.call{value: totalAmount}(functionCalldata);
            if (!success) revert RefundExecutionFailed();
        }

        emit Refunded(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate total amount from inputs
     * @param inputs Array of input tokens [address, amount]
     */
    function _calculateTotalAmount(uint256[2][] calldata inputs) internal pure returns (uint256 totalAmount) {
        for (uint256 i = 0; i < inputs.length; i++) {
            totalAmount += inputs[i][1];
        }
    }

    /**
     * @notice Collect and validate native ETH inputs
     * @param inputs Array of input tokens [address, amount]
     */
    function _collectInputs(uint256[2][] calldata inputs) internal {
        if (inputs.length == 0) revert InvalidAmount();

        uint256 expectedEthValue = 0;

        for (uint256 i = 0; i < inputs.length; i++) {
            uint256 assetId = inputs[i][0];
            uint256 amount = inputs[i][1];

            // Only native ETH (zero address) is supported
            if (assetId != 0) revert InvalidAsset();

            expectedEthValue += amount;
        }

        // Verify sufficient ETH was sent
        if (msg.value < expectedEthValue) revert InvalidAmount();

        // ETH is now escrowed in this contract
    }

    function _validateIntent(ShinobiIntent calldata intent) internal view {
        // Validate origin chain
        if (intent.originChainId != block.chainid) revert InvalidChain();

        // Validate deadlines
        if (block.timestamp >= intent.fillDeadline) revert TimestampPassed();
        if (block.timestamp >= intent.expires) revert TimestampPassed();
        if (intent.expires <= intent.fillDeadline) revert TimestampPassed();

        // Validate has inputs
        if (intent.inputs.length == 0) revert InvalidAmount();

        // Validate has outputs
        if (intent.outputs.length == 0) revert InvalidAmount();
    }

    /**
     * @notice Validates that caller is the order owner/solver (STANDARD OIF)
     * @dev Only reads rightmost 20 bytes to verify the owner
     * @param orderOwner The solver address (left-padded to bytes32)
     */
    function _orderOwnerIsCaller(bytes32 orderOwner) internal view {
        if (_bytes32ToAddress(orderOwner) != msg.sender) revert NotOrderOwner();
    }

    /**
     * @notice Validates fills via oracle (STANDARD OIF PATTERN)
     * @dev Builds proof series that binds solver+orderId+timestamp to each output
     * @dev Oracle attestation proves the specific solver filled the specific output
     * @param intent The intent being finalized
     * @param orderId The computed order identifier
     * @param solveParams Array of solve parameters (one per output)
     */
    function _validateFills(
        ShinobiIntent calldata intent,
        bytes32 orderId,
        IShinobiInputSettler.SolveParams[] calldata solveParams
    ) internal view {
        uint256 numOutputs = intent.outputs.length;

        // Validate we have solve params for all outputs
        if (solveParams.length != numOutputs) revert InvalidSolveParamsLength();

        // Build proof series for oracle validation (standard OIF format)
        bytes memory proofSeries = new bytes(128 * numOutputs);

        for (uint256 i = 0; i < numOutputs; i++) {
            uint32 outputFilledAt = solveParams[i].timestamp;

            // Validate output was filled before deadline
            if (intent.fillDeadline < outputFilledAt) {
                revert FilledTooLate(intent.fillDeadline, outputFilledAt);
            }

            // Build payload hash: keccak256(solver | orderId | timestamp | output)
            // This binds the solver address to this specific fill
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

            bytes32 payloadHash = keccak256(
                MandateOutputEncodingLib.encodeFillDescriptionMemory(
                    solveParams[i].solver,
                    orderId,
                    outputFilledAt,
                    output
                )
            );

            // Pack into proof series: chainId | oracle | settler | payloadHash
            bytes32 remoteChainId = bytes32(output.chainId);
            bytes32 remoteOracle = output.oracle;
            bytes32 remoteSettler = output.settler;

            assembly {
                let offset := add(proofSeries, add(32, mul(i, 128)))
                mstore(offset, remoteChainId)
                mstore(add(offset, 32), remoteOracle)
                mstore(add(offset, 64), remoteSettler)
                mstore(add(offset, 96), payloadHash)
            }
        }

        // Validate via fill oracle - proves the specific solver filled each output
        IInputOracle(intent.fillOracle).efficientRequireProven(proofSeries);
    }

    /**
     * @notice Convert bytes32 to address (standard OIF helper)
     * @param b The bytes32 value (left-padded address)
     * @return addr The address (rightmost 20 bytes)
     */
    function _bytes32ToAddress(bytes32 b) internal pure returns (address addr) {
        assembly {
            addr := b
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function orderIdentifier(ShinobiIntent memory intent) public pure override returns (bytes32) {
        return intent.orderIdentifier();
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the entrypoint address
     * @dev Can only be called once during deployment setup
     * @dev NOTE: In production, add access control or pass in constructor
     * @param _entrypoint Address of the entrypoint contract
     */
    function setEntrypoint(address _entrypoint) external {
        require(entrypoint == address(0), "Entrypoint already set");
        require(_entrypoint != address(0), "Invalid address");
        entrypoint = _entrypoint;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
