// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {Entrypoint} from "contracts/Entrypoint.sol";
import {CrossChainProofLib} from "./lib/CrossChainProofLib.sol";
import {ShinobiCashPool} from "./ShinobiCashPool.sol";
import {ShinobiCashPoolSimple} from "./implementations/ShinobiCashPoolSimple.sol";
import {IExtendedOrder} from "../oif/interfaces/IExtendedOrder.sol";
import {ExtendedOrderLib} from "../oif/lib/ExtendedOrderLib.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IShinobiCashCrossChainHandler} from "./interfaces/IShinobiCashCrossChainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title ShinobiCashEntrypoint
 * @notice Extends Entrypoint with cross-chain withdrawal capabilities
 */
contract ShinobiCashEntrypoint is Entrypoint, IShinobiCashCrossChainHandler {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;
    using ExtendedOrderLib for IExtendedOrder.ExtendedOrder;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping of chain IDs to their support status
    mapping(uint256 chainId => bool isSupported) public supportedChains;
    
    
    /// @notice Address of the Extended OIF InputSettler authorized to call handleRefund
    address public extendedInputSettler;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when a chain's support status is updated
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);


    /// @notice Emitted when a cross-chain refund is processed
    event RefundProcessed(
        uint256 amount,
        uint256 indexed refundCommitmentHash
    );

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @inheritdoc IShinobiCashCrossChainHandler
    function processCrossChainWithdrawal(
        CrossChainWithdrawal calldata withdrawal,
        CrossChainWithdrawProof calldata proof,
        uint256 scope,
        CrossChainIntentParams calldata intentParams
    ) external override nonReentrant {
        CrossChainRelayData memory relayData = abi.decode(withdrawal.data, (CrossChainRelayData));
        
        uint256 destinationChain = uint256(relayData.encodedDestination) >> 224;
        // address recipient = address(uint160(uint256(relayData.encodedDestination)));
        
        require(supportedChains[destinationChain], "Destination chain not supported");
        
        IPrivacyPool basePool = scopeToPool[scope];
        require(address(basePool) != address(0), "Pool not found");
        
        ShinobiCashPool shinobiPool = ShinobiCashPool(address(basePool));
        require(shinobiPool.supportsCrossChain(), "Pool does not support cross-chain");
        
        IERC20 asset = IERC20(shinobiPool.ASSET());
        
        require(
            relayData.relayFeeBPS <= assetConfig[asset].maxRelayFeeBPS,
            "Relay fee exceeds maximum"
        );
        
        shinobiPool.crossChainWithdraw(
            IPrivacyPool.Withdrawal({
                processooor: address(this),
                data: withdrawal.data
            }),
            CrossChainProofLib.CrossChainWithdrawProof({
                pA: proof.pA,
                pB: proof.pB,
                pC: proof.pC,
                pubSignals: proof.pubSignals
            })
        );
        
        uint256 withdrawnAmount = proof.pubSignals[2];
        uint256 feeAmount = (withdrawnAmount * relayData.relayFeeBPS) / 10000;
        uint256 netAmount = withdrawnAmount - feeAmount;
        uint256 nullifierHash = proof.pubSignals[1];
        
        // Validate ExtendedInputSettler is set
        require(extendedInputSettler != address(0), "ExtendedInputSettler not set");
        
        // Validate intent parameters for OIF order creation
        _validateIntentParams(intentParams, withdrawnAmount);
        
        if (feeAmount > 0) {
            _transfer(asset, relayData.feeRecipient, feeAmount);
        }
        
        // Create and submit ExtendedOrder to OIF InputSettler
        _createAndSubmitOIFOrder(
            intentParams,
            bytes32(nullifierHash),
            bytes32(proof.pubSignals[8]), // refundCommitmentHash 
            netAmount,
            scope
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update the support status for a chain
    /// @param chainId The chain ID to update
    /// @param supported Whether the chain is supported
    function updateChainSupport(uint256 chainId, bool supported) external onlyRole(_OWNER_ROLE) {
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /// @notice Set the Extended OIF InputSettler address
    /// @param _inputSettler The address of the Extended InputSettler contract
    function setExtendedInputSettler(address _inputSettler) external onlyRole(_OWNER_ROLE) {
        require(_inputSettler != address(0), "InputSettler address cannot be zero");
        extendedInputSettler = _inputSettler;
    }

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the Extended OIF InputSettler
     * @dev Forwards ETH to privacy pool for refund commitment creation
     * @param _refundCommitmentHash The commitment hash for refund (from 9th signal of original proof)
     * @param _amount The amount being refunded (escrowed amount from OIF)
     * @param _scope The privacy pool scope identifier
     */
    function handleRefund(
        uint256 _refundCommitmentHash,
        uint256 _amount,
        uint256 _scope
    ) external payable  {
        // Only Extended OIF InputSettler can call this function
        require(msg.sender == extendedInputSettler, "Only InputSettler can call handleRefund");
        require(msg.value == _amount, "ETH amount mismatch");
        
        // Get the privacy pool for this scope
        IPrivacyPool basePool = scopeToPool[_scope];
        require(address(basePool) != address(0), "Pool not found");
        
        // Forward ETH to privacy pool for refund commitment insertion
        ShinobiCashPool shinobiPool = ShinobiCashPool(address(basePool));
        shinobiPool.handleRefund{value: msg.value}(_refundCommitmentHash, _amount);
        
        emit RefundProcessed(_amount, _refundCommitmentHash);
    }

    /// @inheritdoc IShinobiCashCrossChainHandler
    function isChainSupported(uint256 chainId) external view override returns (bool) {
        return supportedChains[chainId];
    }

    

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

 /**
     * @notice Create ExtendedOrder and submit to OIF InputSettler
     * @param intentParams User-provided validated intent parameters
     * @param nullifierHash The nullifier hash from privacy pool withdrawal
     * @param refundCommitmentHash The commitment hash for refund recovery
     * @param netAmount The net amount after fees
     * @param scope The privacy pool scope identifier
     */
    function _createAndSubmitOIFOrder(
        CrossChainIntentParams calldata intentParams,
        bytes32 nullifierHash,
        bytes32 refundCommitmentHash,
        uint256 netAmount,
        uint256 scope
    ) internal {
        // Calculate refund calldata hash internally
        bytes memory refundCalldata = abi.encode(
            address(this), // target: ShinobiCashEntrypoint
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(refundCommitmentHash), // refund commitment hash
                netAmount,                     // refund amount
                scope                          // privacy pool scope
            )
        );
        bytes32 refundCalldataHash = keccak256(refundCalldata);
        
        // Create Extended order using validated parameters
        IExtendedOrder.ExtendedOrder memory order = IExtendedOrder.ExtendedOrder({
            user: address(this), // ShinobiCashEntrypoint creates the order
            nonce: uint256(nullifierHash), // Use nullifier hash as nonce for uniqueness
            originChainId: block.chainid, // Current chain
            expires: intentParams.expires, // User-provided expiry
            fillDeadline: intentParams.fillDeadline, // User-provided fill deadline
            inputOracle: intentParams.inputOracle, // User-provided oracle
            inputs: intentParams.inputs, // User-provided inputs
            outputs: intentParams.outputs, // User-provided outputs
            refundCalldataHash: refundCalldataHash // Calculated refund calldata hash
        });
        
        // Submit order to ExtendedInputSettler
        IExtendedOrder(extendedInputSettler).openExtended{value: netAmount}(order);
    }

    /**
     * @notice Validate intent parameters for OIF order creation
     * @param intentParams User-provided intent parameters
     * @param totalAmount Total amount to be escrowed (withdrawn amount)
     */
    function _validateIntentParams(
        CrossChainIntentParams calldata intentParams,
        uint256 totalAmount
    ) internal view {
        // Validate timing parameters
        require(
            intentParams.fillDeadline > block.timestamp,
            "Fill deadline must be in the future"
        );
        require(
            intentParams.expires > intentParams.fillDeadline,
            "Expiry must be after fill deadline"
        );
        require(
            intentParams.expires <= block.timestamp + 24 hours,
            "Expiry too far in the future (max 24 hours)"
        );

        // Validate inputs match the total amount
        require(intentParams.inputs.length == 1, "Must have exactly one input");
        require(
            intentParams.inputs[0][0] == 0, // Native ETH
            "Input must be native ETH (address 0)"
        );
        require(
            intentParams.inputs[0][1] == totalAmount,
            "Input amount must match total withdrawn amount"
        );

        // Validate outputs are not empty
        require(intentParams.outputs.length > 0, "Must have at least one output");
    }
 
}
