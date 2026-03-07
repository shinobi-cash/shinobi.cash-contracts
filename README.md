# Shinobi.cash Contracts

Cross-chain privacy protocol combining zero-knowledge proofs with intent-based settlement. Deposit on one chain, withdraw privately on another.

> **WARNING**: Under active development. Not audited. Testnet only.

## Architecture

**ShinobiPool** — ERC-8153 diamond proxy that serves as the single-address privacy pool. All operations (deposit, withdraw, ragequit) are implemented as actions routed via `delegatecall`.

### Core Components

| Component | Purpose |
|-----------|---------|
| **ShinobiPool** | ERC-8153 proxy — deposits, withdrawals, governance, config |
| **Actions** (7 facets) | DepositAction, WithdrawAction, Withdraw2Action, CrosschainWithdrawAction, CrosschainWithdraw2Action, CrosschainDepositAction, RagequitAction |
| **OIF Settlers** | Cross-chain intent escrow and settlement |
| **Paymasters** (4) | ERC-4337 gasless withdrawals with ZK proof validation |
| **Verifiers** (5) | Groth16 SNARK proof verification |

### How It Works

1. **Deposit** — User sends ETH to ShinobiPool, a Poseidon commitment is added to the Merkle tree
2. **Withdraw** — User generates a ZK proof ("I know a secret in this tree") and withdraws to a fresh address
3. **Cross-chain** — Withdrawal creates an OIF intent, solvers fill on the destination chain, Hyperlane relays proof back
4. **Privacy** — ZK proofs make deposits and withdrawals cryptographically unlinkable

### Modular Action Architecture

ShinobiPool uses ERC-8153 to split operations into independent **action contracts** (facets). Each action is a standalone contract deployed once and registered with ShinobiPool — the proxy routes calls via selector → action lookup and executes them with `delegatecall`.

```
User tx → ShinobiPool (fallback)
            ├─ selector lookup in RoutingStorage
            └─ delegatecall → Action contract
                               ├─ reads/writes shared PoolStorage
                               └─ returns result to caller
```

**What's upgradeable (actions):**

| Action | Operation | Proof Signals |
|--------|-----------|---------------|
| DepositAction | Same-chain deposit | — |
| CrosschainDepositAction | Cross-chain deposit (called by settler) | — |
| WithdrawAction | Same-chain 1:1 withdrawal | 8 |
| Withdraw2Action | Same-chain 2:1 merge | 9 |
| CrosschainWithdrawAction | Cross-chain 1:1 withdrawal | 11 |
| CrosschainWithdraw2Action | Cross-chain 2:1 merge | 12 |
| RagequitAction | Emergency exit by depositor | 4 |

**What's built-in (currently):** Governance, pool config, ASP root updates, loupe, views. These live in ShinobiPool directly but may be modularized in the future — e.g., swappable compliance mechanisms (ASP, Proof of Innocence, or none).

**Shared state:** All actions read/write a single `PoolStorage` (EIP-7201 namespaced) containing the Merkle tree, nullifiers, fee config, and chain config. Actions are stateless — they can be replaced without migrating data.

### Key Technologies

- **ZK-SNARKs** (Groth16) for privacy proofs
- **Open Intent Framework** for cross-chain settlement with decentralized solvers
- **ERC-4337** paymasters for gasless withdrawals
- **Hyperlane** for cross-chain intent proof relay
- **EIP-1153** transient storage for reentrancy guards

## Commands

```bash
forge build            # Compile
forge test             # Run tests
forge test -vvv        # Verbose output
forge test --gas-report
```

## License

GPL-3.0 — see [LICENSE](LICENSE)
