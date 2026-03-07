// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @notice Relay data for same-chain withdrawals
struct WithdrawData {
    address recipient;
    address feeRecipient;
    uint256 relayFeeBPS;
}

/// @notice Decoded relay data for cross-chain withdrawals
struct CrosschainWithdrawData {
    address feeRecipient;          // Receives relay fee (withdrawal) and refund fee (if refund triggered)
    uint256 solverFeeBPS;          // Solver fee in basis points (not in circuit)
    bytes32 encodedDestination;    // chainId(32 bits) + recipient(160 bits) packed
}
