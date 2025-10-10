// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {Entrypoint} from "contracts/Entrypoint.sol";
import {CrossChainProofLib} from "./lib/CrossChainProofLib.sol";
import {ShinobiCashPool} from "./ShinobiCashPool.sol";
import {ShinobiCashPoolSimple} from "./implementations/ShinobiCashPoolSimple.sol";
import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";
import {IERC20} from "@oz/interfaces/IERC20.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {IShinobiCashCrossChainHandler} from "./interfaces/IShinobiCashCrossChainHandler.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ShinobiIntent} from "../oif/types/ShinobiIntentType.sol";
import {IShinobiInputSettler} from "../oif/interfaces/IShinobiInputSettler.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title ShinobiCashEntrypoint
 * @notice Extends Entrypoint with cross-chain withdrawal capabilities
 */
contract ShinobiCashEntrypoint is Entrypoint, IShinobiCashCrossChainHandler {
    using CrossChainProofLib for CrossChainProofLib.CrossChainWithdrawProof;

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping of chain IDs to their support status
    mapping(uint256 chainId => bool isSupported) public supportedChains;


    /// @notice Address of the ShinobiInputSettler for cross-chain withdrawals
    address public inputSettler;

    /// @notice Address of the DepositOutputSettler for cross-chain deposits
    address public depositOutputSettler;

    /// @notice Intent oracle address (for deposits - not used for withdrawals)
    address public intentOracle;

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
        IPrivacyPool.Withdrawal calldata withdrawal,
        CrossChainProofLib.CrossChainWithdrawProof calldata proof,
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
        
        shinobiPool.crossChainWithdraw(withdrawal, proof);
        
        uint256 withdrawnAmount = proof.withdrawnValue();
        uint256 feeAmount = (withdrawnAmount * relayData.relayFeeBPS) / 10000;
        uint256 netAmount = withdrawnAmount - feeAmount;
        uint256 nullifierHash = proof.existingNullifierHash();
        
        // Validate ShinobiInputSettler is set
        require(inputSettler != address(0), "InputSettler not set");

        if (feeAmount > 0) {
            _transfer(asset, relayData.feeRecipient, feeAmount);
        }

        // Create and submit ShinobiIntent to WithdrawalInputSettler
        _createAndSubmitOIFOrder(
            intentParams,
            bytes32(nullifierHash),
            bytes32(proof.pubSignals[8]), // refundCommitmentHash 
            netAmount,
            scope
        );
        emit WithdrawalRelayed(msg.sender, address(uint160(uint256(relayData.encodedDestination))), asset, withdrawnAmount, feeAmount);
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

    /// @notice Set the ShinobiInputSettler address
    /// @param _inputSettler The address of the ShinobiInputSettler contract
    function setInputSettler(address _inputSettler) external onlyRole(_OWNER_ROLE) {
        require(_inputSettler != address(0), "InputSettler address cannot be zero");
        inputSettler = _inputSettler;
    }

    /// @notice Set the DepositOutputSettler address
    /// @param _outputSettler The address of the DepositOutputSettler contract
    function setDepositOutputSettler(address _outputSettler) external onlyRole(_OWNER_ROLE) {
        require(_outputSettler != address(0), "OutputSettler address cannot be zero");
        depositOutputSettler = _outputSettler;
    }

    /// @notice Set the intent oracle address (used for deposits, not withdrawals)
    /// @param _intentOracle The address of the intent oracle contract
    function setIntentOracle(address _intentOracle) external onlyRole(_OWNER_ROLE) {
        intentOracle = _intentOracle;
    }

    /**
     * @notice Handle refund for failed cross-chain withdrawal
     * @dev Can only be called by the WithdrawalInputSettler
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
        // Only ShinobiInputSettler can call this function
        require(msg.sender == inputSettler, "Only InputSettler can call handleRefund");
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

    /**
     * @notice Handle cross-chain deposit with verified depositor address
     * @dev Called by DepositOutputSettler after intent proof validation
     * @dev CRITICAL: depositor parameter comes from VERIFIED intent.user via intent proof
     * @param depositor The verified depositor address from origin chain
     * @param amount The deposit amount
     * @param precommitment The precommitment for the deposit
     */
    function crossChainDeposit(
        address depositor,
        uint256 amount,
        uint256 precommitment
    ) external payable nonReentrant {
        // CRITICAL: Only DepositOutputSettler can call this
        // This ensures the depositor was verified via intent proof
        require(msg.sender == depositOutputSettler, "Only DepositOutputSettler");

        // Validate amount matches msg.value
        require(msg.value == amount, "Amount mismatch");

        // Get the native ETH pool
        IERC20 asset = IERC20(Constants.NATIVE_ASSET);
        AssetConfig memory config = assetConfig[asset];
        IPrivacyPool pool = config.pool;
        require(address(pool) != address(0), "Pool not found");

        // Check if the precommitment has already been used
        require(!usedPrecommitments[precommitment], "Precommitment already used");
        usedPrecommitments[precommitment] = true;

        // Check minimum deposit amount
        require(amount >= config.minimumDepositAmount, "Below minimum deposit");

        // Deduct vetting fees
        uint256 amountAfterFees = _deductFee(amount, config.vettingFeeBPS);

        // Deposit to pool with VERIFIED depositor address
        // This maintains ASP compliance since depositor was verified via intent proof
        uint256 commitment = pool.deposit{value: amountAfterFees}(depositor, amountAfterFees, precommitment);

        emit Deposited(depositor, pool, commitment, amountAfterFees);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

 /**
     * @notice Create ShinobiIntent and submit to WithdrawalInputSettler
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
        // Create refund calldata for returning to pool as commitment
        bytes memory refundCalldata = abi.encode(
            address(this), // target: ShinobiCashEntrypoint
            abi.encodeWithSelector(
                this.handleRefund.selector,
                uint256(refundCommitmentHash), // refund commitment hash
                netAmount,                     // refund amount
                scope                          // privacy pool scope
            )
        );

        // Create ShinobiIntent for withdrawal
        ShinobiIntent memory intent = ShinobiIntent({
            user: address(this),                        // ShinobiCashEntrypoint creates the order
            nonce: uint256(nullifierHash),              // Use nullifier hash as nonce for uniqueness
            originChainId: block.chainid,               // Current chain (Ethereum)
            expires: intentParams.expires,              // User-provided expiry
            fillDeadline: intentParams.fillDeadline,    // User-provided fill deadline
            fillOracle: intentParams.fillOracle,        // Fill proof oracle (destination → origin)
            inputs: intentParams.inputs,                // User-provided inputs
            outputs: intentParams.outputs,              // User-provided outputs
            intentOracle: address(0),                   // No intent verification needed for withdrawals
            refundCalldata: refundCalldata              // Custom refund logic
        });

        // Submit intent to ShinobiInputSettler
        IShinobiInputSettler(inputSettler).open{value: netAmount}(intent);
    }
 
}
