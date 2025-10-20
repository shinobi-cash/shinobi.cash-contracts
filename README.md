# Shinobi.cash Contracts

**Borderless Privacy for a Multi-Chain World**

Cross-chain privacy protocol enabling users to deposit on one blockchain and withdraw privately on another, combining zero-knowledge proofs with decentralized intent-based settlement.

> ⚠️ **WARNING: Under Active Development**
>
> This project is currently in development and has **not been audited**. Do not use in production or with real funds. Testnet only.

---

## What is Shinobi.cash?

Shinobi.cash solves cross-chain privacy by unifying privacy pools across multiple chains. Users can:
- Deposit ETH on Base
- Withdraw privately on Arbitrum (or any supported chain)
- Maintain cryptographic unlinkability between deposits and withdrawals

**Privacy comes from:** ZK-SNARKs, Merkle tree commitments, and nullifiers
**Cross-chain settlement via:** Open Intent Framework (OIF) with decentralized solvers

---

## Architecture Overview

### Privacy Layer

**Core Components:**
- **ShinobiCashPool**: Privacy pool with cross-chain withdrawal support and refund commitment handling
- **ShinobiCashEntrypoint**: Manages cross-chain withdrawals, creates OIF intents, handles refunds
- **Merkle Tree**: Unified commitment tree across all supported chains
- **ZK Proofs**: Groth16 SNARKs prove commitment ownership without revealing which one

**How Privacy Works:**
1. User deposits → generates secret commitment → added to Merkle tree
2. Days/weeks later, user proves via ZK proof: "I know a secret in this tree"
3. Withdrawal occurs on different chain with fresh address
4. ZK proof makes deposit and withdrawal cryptographically unlinkable

### Cross-Chain Settlement Layer

**OIF Integration:**
- **ShinobiInputSettler**: Manages intent creation and escrow on origin chain
- **ShinobiDepositOutputSettler**: Validates deposit intents via oracle (prevents spoofing)
- **ShinobiWithdrawalOutputSettler**: Handles withdrawal fills (ZK proof already validated)

**Dual Oracle System:**
- **Intent Oracle**: Validates deposit intents were created by legitimate users
- **Fill Oracle**: Validates solvers delivered funds before releasing escrow

**Decentralized Solver Network:**
- Permissionless solvers compete to fill cross-chain intents
- No trusted bridge operator
- Atomic settlement guarantees via oracle validation

### Account Abstraction Layer

**ERC-4337 Paymasters:**
- **CrossChainWithdrawalPaymaster**: Sponsors gas for cross-chain withdrawals after ZK proof validation
- **SimpleShinobiCashPoolPaymaster**: Sponsors gas for standard privacy pool operations

Enables gasless withdrawals — users don't need destination chain gas tokens.

---

## Key Contracts

### Privacy & Entrypoint
| Contract | Purpose |
|----------|---------|
| `ShinobiCashPool` | Privacy pool with cross-chain support |
| `ShinobiCashPoolSimple` | Simple implementation for ETH privacy pool |
| `ShinobiCashEntrypoint` | Cross-chain withdrawal processing & intent creation |
| `ShinobiCrosschainDepositEntrypoint` | Lightweight deposit entrypoint for origin chains |

### OIF Settlers
| Contract | Purpose |
|----------|---------|
| `ShinobiInputSettler` | Intent creation & escrow (origin chain) |
| `ShinobiDepositOutputSettler` | Deposit intent validation (destination/pool chain) |
| `ShinobiWithdrawalOutputSettler` | Withdrawal fill handling (destination/user chain) |

### Verification
| Contract | Purpose |
|----------|---------|
| `CrossChainWithdrawalVerifier` | Verifies cross-chain withdrawal ZK proofs |
| `CommitmentVerifier` | Verifies deposit commitment proofs |
| `CrossChainWithdrawalProofVerifier` | Validates cross-chain withdrawal proof structure |

### Account Abstraction
| Contract | Purpose |
|----------|---------|
| `CrossChainWithdrawalPaymaster` | Sponsors gas for cross-chain withdrawals |
| `SimpleShinobiCashPoolPaymaster` | Sponsors gas for standard operations |

---

## License

Apache-2.0 - see [LICENSE](LICENSE) for details

---

*Built with ❤️ for Ethereum privacy*

**Because privacy shouldn't stop at chain boundaries.** 🥷✨
