// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Karandeep Singh (https://github.com/KannuSingh)

pragma solidity 0.8.28;

import {MandateOutput} from "oif-contracts/input/types/MandateOutputType.sol";

/**
 * @notice Extended StandardOrder for Shinobi.cash cross-chain operations
 * @dev Single structure for both withdrawal and deposit intents
 * @dev Extends OIF StandardOrder with bidirectional oracle support and custom refund logic
 */
struct ShinobiIntent {
    // === Base StandardOrder Fields ===

    /// @notice Intent creator (verified via msg.sender on origin chain)
    address user;

    /// @notice User nonce for uniqueness
    uint256 nonce;

    /// @notice Chain where intent was created
    uint256 originChainId;

    /// @notice Expiry timestamp for refunds
    uint32 expires;

    /// @notice Deadline for filling the intent
    uint32 fillDeadline;

    /// @notice Oracle for fill proof validation (destination → origin)
    /// @dev Proves that outputs were filled on destination chain
    address fillOracle;

    /// @notice Input tokens to be escrowed [tokenId, amount][]
    uint256[2][] inputs;

    /// @notice Outputs to be filled on destination chain
    MandateOutput[] outputs;

    // === Shinobi Extensions ===

    /// @notice Oracle for intent proof validation (origin → destination)
    /// @dev Proves that intent was created by verified user on origin chain
    /// @dev Critical for deposits to prevent depositor address spoofing
    address intentOracle;

    /// @notice Custom refund calldata for protocol-specific refund logic
    /// @dev If empty (0x), performs simple ETH transfer to intent.user
    /// @dev If present, executes custom refund (e.g., return to privacy pool as commitment)
    bytes refundCalldata;
}
