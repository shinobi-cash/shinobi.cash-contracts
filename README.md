# Shinobi Cash Contracts

Privacy-preserving cross-chain withdrawal system built on Account Abstraction and zero-knowledge proofs.

## Core Contracts

### Privacy Pool System
- **ShinobiCashPool**: Abstract privacy pool extending PrivacyPool with cross-chain withdrawal capabilities and refund commitment handling
- **ShinobiCashEntrypoint**: Extends base Entrypoint with cross-chain withdrawal processing, manages supported chains and OIF order creation

### Cross-Chain Infrastructure  
- **ExtendedInputSettler**: OIF InputSettlerEscrow extension supporting custom refund calldata execution for protocol-specific refund logic
- **CrossChainWithdrawalPaymaster**: ERC-4337 paymaster sponsoring cross-chain withdrawals after validating ZK proofs and withdrawal economics

### Verification & Oracles
- **CrossChainWithdrawalVerifier**: Groth16 verifier for cross-chain withdrawal ZK proofs ensuring withdrawal authenticity across chains
- **CommitmentVerifier**: Groth16 verifier for deposit commitment proofs maintaining privacy pool integrity

### Supporting Libraries
- **CrossChainProofLib**: Library for parsing and validating cross-chain withdrawal ZK proof public signals and context data
- **ExtendedOrderLib**: OIF utilities for converting between ExtendedOrder and StandardOrder formats with hash computation
- **ProofLib**: Common proof verification utilities and helper functions for privacy pool operations

## Architecture

The system enables private cross-chain withdrawals where users deposit on one chain and withdraw on another without revealing transaction links. Uses ERC-4337 for gasless UX and OIF protocol for cross-chain intent settlement.

Built on top of [Privacy Pools](https://github.com/0xbow-io/privacy-pools-core/tree/main/packages/contracts) for the core privacy-preserving mixing functionality.
