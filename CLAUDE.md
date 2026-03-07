# CLAUDE.md - Shinobi.cash Contracts

This file provides guidance to Claude Code when working with the Shinobi.cash smart contracts repository.

## Project Overview

Shinobi.cash Contracts is a cross-chain privacy protocol enabling users to deposit on one blockchain and withdraw privately on another. The system combines:
- **Zero-knowledge proofs** (Groth16 SNARKs) for privacy
- **ERC-8153 Diamond proxy** (ShinobiPool) as single-address privacy pool
- **Open Intent Framework (OIF)** for cross-chain settlement
- **ERC-4337 Account Abstraction** for gasless withdrawals
- **Hyperlane** for cross-chain intent proof relay

> **WARNING**: This project is under active development and has NOT been audited. Testnet only.

For detailed architecture documentation, see `src/ARCHITECTURE.md`.

---

## Common Commands

```bash
# Build & Test
pnpm build              # Build contracts via Foundry
pnpm test               # Run tests
pnpm clean              # Clean artifacts

# Foundry Commands
forge build             # Compile contracts
forge test              # Run tests
forge test -vvv         # Verbose test output
forge test --match-test testDeposit  # Run specific test
forge test --gas-report # Gas report

# Deploy (example — pool chain pipeline)
POOL_KEY=arbitrum-sepolia forge script script/pool/09_Deploy_ShinobiPool.s.sol:Deploy_ShinobiPool \
  --rpc-url arbitrum-sepolia --broadcast --verify
```

---

## Directory Structure

```
shinobi.cash-contracts/
├── src/
│   ├── pool/                          # ERC-8153 diamond pool (pool chain)
│   │   ├── ShinobiPool.sol             #   Diamond proxy (fallback routing + built-in governance/views)
│   │   ├── FacetBase.sol              #   Shared modifiers (reentrancy, admin, roles, lifecycle)
│   │   ├── facets/                    #   Operational facets (delegatecall targets)
│   │   │   ├── DepositAction.sol      #     Same-chain deposits
│   │   │   ├── CrosschainDepositAction.sol  # Cross-chain deposits (called by settler)
│   │   │   ├── WithdrawAction.sol     #     Same-chain 1:1 withdrawal (8-signal proof)
│   │   │   ├── Withdraw2Action.sol    #     Same-chain 2:1 merge (9-signal proof)
│   │   │   ├── CrosschainWithdrawAction.sol # Cross-chain 1:1 (11-signal) + handleRefund
│   │   │   ├── CrosschainWithdraw2Action.sol# Cross-chain 2:1 (12-signal) + handleRefund2
│   │   │   └── RagequitAction.sol     #     Emergency withdrawal by depositor (4-signal)
│   │   ├── storage/                   #   Diamond storage (EIP-7201 namespaced slots)
│   │   │   ├── PoolStorage.sol        #     All pool state: Merkle tree, nullifiers, config
│   │   │   ├── RoutingStorage.sol     #     Selector → facet routing
│   │   │   └── AccessControlStorage.sol  #  Admin + role-based access
│   │   ├── libraries/                 #   Shared internal logic
│   │   │   ├── Types.sol              #     WithdrawData, CrosschainWithdrawData structs
│   │   │   ├── Constants.sol          #     SNARK_SCALAR_FIELD, NATIVE_ASSET
│   │   │   ├── PoolOps.sol            #     Insert, spend, validate, fees, context
│   │   │   ├── RoutingOps.sol         #     Facet add/replace/remove
│   │   │   ├── AccessControlOps.sol   #     Admin check + role grant/revoke
│   │   │   ├── IntentOps.sol          #     Cross-chain OIF intent construction
│   │   │   └── RefundOps.sol          #     Shared refund logic for crosschain facets
│   │   └── interfaces/
│   │       ├── IFacet.sol             #     ERC-8153 selector export
│   │       └── IShinobiPool.sol        #     Combined interface for callers
│   │
│   ├── crosschain/                    # Deployed on origin chains (e.g., Base)
│   │   └── ShinobiCrosschainDepositEntrypoint.sol  # User deposits here
│   │
│   ├── paymaster/                     # ERC-4337 paymasters for gasless withdrawals
│   │   ├── WithdrawalPaymaster.sol              # Same-chain 1:1 (8-signal)
│   │   ├── CrosschainWithdrawalPaymaster.sol    # Cross-chain 1:1 + refund (11-signal)
│   │   ├── Withdraw2Paymaster.sol               # Same-chain 2:1 merge (9-signal)
│   │   └── CrosschainWithdraw2Paymaster.sol     # Cross-chain 2:1 + refund (12-signal)
│   │
│   ├── oif/                           # Open Intent Framework (cross-chain settlement)
│   │   ├── ShinobiInputSettler.sol    #   Escrows ETH for cross-chain ops
│   │   ├── ShinobiDepositOutputSettler.sol      # Fills deposits (pool chain)
│   │   ├── ShinobiWithdrawalOutputSettler.sol   # Fills withdrawals (origin chain)
│   │   ├── BaseShinobiOutputSettler.sol          # Shared output settler base
│   │   ├── interfaces/                #   IShinobiInputSettler, IShinobiOutputSettler, etc.
│   │   ├── libraries/                 #   ShinobiIntentType, ShinobiIntentLib
│   │   └── hyperlane/                 #   HyperlaneOracle + Hyperlane external deps
│   │
│   ├── proofLibs/                     # Proof signal accessor libraries
│   │   ├── WithdrawProofLib.sol       #   8 signals (same-chain 1:1)
│   │   ├── CrosschainProofLib.sol     #   11 signals (cross-chain 1:1)
│   │   ├── Withdraw2ProofLib.sol      #   9 signals (same-chain 2:1)
│   │   ├── CrosschainWithdraw2ProofLib.sol  # 12 signals (cross-chain 2:1)
│   │   └── RagequitProofLib.sol       #   4 signals (emergency exit)
│   │
│   ├── verifiers/                     # Groth16 verifiers (auto-generated by snarkjs)
│   │   ├── WithdrawalVerifier.sol
│   │   ├── CrosschainWithdrawalVerifier.sol
│   │   ├── Withdraw2Verifier.sol
│   │   ├── CrosschainWithdraw2Verifier.sol
│   │   ├── CommitmentVerifier.sol
│   │   └── interfaces/                #   IWithdrawalVerifier, ICrosschainWithdrawalProofVerifier, etc.
│   │
│   ├── mocks/MockOracle.sol           # Test mock (always returns true)
│   └── ARCHITECTURE.md                # Detailed architecture documentation
│
├── script/
│   ├── pool/                          # Pool chain deployment pipeline (steps 01-14)
│   │   ├── 01_Deploy_Verifiers.s.sol          # Deploy 5 ZK verifiers
│   │   ├── 02_Deploy_DepositAction.s.sol      # Deploy DepositAction facet
│   │   ├── 03_Deploy_CrosschainDepositAction.s.sol
│   │   ├── 04_Deploy_WithdrawAction.s.sol
│   │   ├── 05_Deploy_CrosschainWithdrawAction.s.sol
│   │   ├── 06_Deploy_Withdraw2Action.s.sol
│   │   ├── 07_Deploy_CrosschainWithdraw2Action.s.sol
│   │   ├── 08_Deploy_RagequitAction.s.sol
│   │   ├── 09_Deploy_ShinobiPool.s.sol         # Deploy ShinobiPool proxy
│   │   ├── 10_Deploy_Settlers.s.sol           # Deploy InputSettler, Oracle, DepositOutputSettler
│   │   ├── 11_Setup_ShinobiPool.s.sol          # Configure pool settings
│   │   ├── 12_Deploy_Paymasters.s.sol         # Deploy 4 paymasters
│   │   ├── 13_Setup_WithdrawalChains.s.sol    # Configure destination chains
│   │   └── 14_Deploy_Timelock.s.sol           # Deploy TimelockController + bootstrap
│   ├── chains/                        # Add new origin chains
│   │   ├── AddChain_01_DeployOriginContracts.s.sol   # Deploy all origin-chain contracts
│   │   ├── AddChain_02_ConfigurePoolChain.s.sol      # Configure deposit settler for origin
│   │   └── AddChain_03_ConfigureOriginChain.s.sol    # Configure origin entrypoint + oracles
│   ├── config/                        # Configuration helpers
│   │   ├── ChainConfig.sol
│   │   ├── DeploymentWriter.sol
│   │   ├── pools/*.json               # Per-pool config
│   │   └── origins/*.json             # Per-origin config
│   └── utils/WithdrawPaymasterDeposits.s.sol
│
├── test/
│   ├── pool/                          # Pool tests
│   │   ├── PoolTestBase.sol           #   Shared test utilities
│   │   ├── ShinobiPool.t.sol           #   Pool admin/config tests
│   │   ├── DepositAction.t.sol
│   │   ├── WithdrawAction.t.sol
│   │   ├── Withdraw2Action.t.sol
│   │   ├── CrosschainWithdrawAction.t.sol
│   │   ├── CrosschainWithdraw2Action.t.sol
│   │   ├── RagequitAction.t.sol
│   │   ├── RefundAction.t.sol
│   │   ├── Integration.t.sol
│   │   └── Timelock.t.sol
│   ├── ShinobiInputSettler.t.sol
│   ├── ShinobiDepositOutputSettler.t.sol
│   ├── ShinobiWithdrawalOutputSettler.t.sol
│   └── ShinobiCrosschainDepositEntrypoint.t.sol
│
├── deployments/                       # Deployment records (JSON)
│   ├── arbitrum-sepolia.json
│   └── base-sepolia.json
├── lib/                               # Git submodule dependencies
├── node_modules/                      # npm dependencies
├── foundry.toml
├── package.json
└── remappings.txt
```

---

## Configuration

### foundry.toml

```toml
[profile.default]
solc_version = '0.8.28'
evm_version = 'cancun'           # Enables EIP-1153 transient storage
optimizer_runs = 10_000
bytecode_hash = "none"           # Reproducible builds
cbor_metadata = false
auto_detect_remappings = false
```

### Key Dependencies (package.json)

```json
{
  "@zk-kit/lean-imt.sol": "^2.0.1",  // Incremental Merkle Tree
  "poseidon-solidity": "^0.0.5",     // Poseidon hash function
  "maci-crypto": "^1.2.0"            // MACI cryptographic utilities
}
```

### Import Remappings

```
@account-abstraction/=lib/account-abstraction/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@oz/=lib/openzeppelin-contracts/contracts/
@oz-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
interfaces/=lib/privacy-pools-core/packages/contracts/src/interfaces/
contracts/=lib/privacy-pools-core/packages/contracts/src/contracts/
oif/=lib/oif/solidity/src/
oif-contracts/=lib/oif-contracts/src/
lean-imt/=node_modules/@zk-kit/lean-imt.sol/
poseidon-solidity/=node_modules/poseidon-solidity/
```

---

## Architecture Overview

The pool is a single-address **ERC-8153 diamond proxy** (`ShinobiPool`). All pool operations (deposit, withdraw, ragequit) are implemented as facets that execute via `delegatecall` through the diamond's `fallback()`. Governance, configuration, and views are built directly into the pool and cannot be removed.

For the full architecture deep dive, see `src/ARCHITECTURE.md`.

### Deployment Topology

```
Pool Chain (Arbitrum)           Origin Chain (Base)
┌─────────────────────┐        ┌───────────────────────────────┐
│  ShinobiPool         │        │  ShinobiCrosschainDepositEntry│
│  ├ DepositAction    │        │  ShinobiWithdrawalOutputSettler│
│  ├ WithdrawAction   │        │  ShinobiInputSettler          │
│  ├ Withdraw2Action  │        │  HyperlaneOracle              │
│  ├ CrosschainWithdrawAction│ └───────────────────────────────┘
│  ├ CrosschainWithdraw2Action│
│  ├ CrosschainDepositAction│
│  └ RagequitAction   │
│  Paymasters (x4)    │
│  ShinobiInputSettler│
│  DepositOutputSettler│
│  HyperlaneOracle    │
└─────────────────────┘
```

---

## Core Data Types

### Withdrawal Data (src/pool/libraries/Types.sol)

Facets accept concrete typed data directly — no wrapper struct.

```solidity
/// Same-chain withdrawal
struct WithdrawData {
    address recipient;
    address feeRecipient;
    uint256 relayFeeBPS;
}

/// Cross-chain withdrawal
struct CrosschainWithdrawData {
    address feeRecipient;
    uint256 solverFeeBPS;
    bytes32 encodedDestination;    // chainId(32 bits) + recipient(160 bits)
}
```

### Context Hash

Binds ZK proofs to specific withdrawal parameters:
```solidity
context = keccak256(abi.encode(abi.encode(data), scope)) % SNARK_SCALAR_FIELD
```

Where `data` is `WithdrawData` or `CrosschainWithdrawData`, and `scope` is the pool's unique identifier.

---

## ShinobiPool

### Key Functions (Facets)

| Facet | Function | Proof Signals | Nullifiers | Intent |
|-------|----------|--------------|------------|--------|
| DepositAction | `deposit(uint256 precommitment)` | — | 0 | No |
| CrosschainDepositAction | `crosschainDeposit(address, uint256, uint256)` | — | 0 | No |
| WithdrawAction | `withdraw(WithdrawData, WithdrawProof)` | 8 | 1 | No |
| Withdraw2Action | `withdraw2(WithdrawData, Withdraw2Proof)` | 9 | 2 | No |
| CrosschainWithdrawAction | `crosschainWithdraw(CrosschainWithdrawData, CrosschainWithdrawProof)` | 11 | 1 | Yes |
| CrosschainWithdraw2Action | `crosschainWithdraw2(CrosschainWithdrawData, CrosschainWithdraw2Proof)` | 12 | 2 | Yes |
| RagequitAction | `ragequit(RagequitProof)` | 4 | 1 | No |

### Withdrawal Flow (all withdrawal facets)

```
1. Check withdrawn value > 0
2. Validate context: keccak256(abi.encode(data), scope) % SNARK_FIELD
3. Validate tree depths within bounds (max 32)
4. Validate state root is in 64-entry circular buffer
5. Validate ASP root is latest
6. Verify Groth16 proof
7. Spend nullifier(s)
8. Insert new commitment
9. Distribute funds (recipient + relay fee)
10. Balance invariant check
```

### Built-in Functions (not removable)

- **Governance**: `transferAdmin`, `acceptAdmin`, `upgradeDiamond`, `grantRole`, `revokeRole`
- **Config**: `setAssetConfig`, `setMaxSolverFeeBPS`, `setMaxRefundFeeBPS`, `setWithdrawalInputSettler`, `setDepositOutputSettler`, `setWithdrawalChainConfig`, `setVettingFeeRecipient`
- **ASP**: `updateRoot(root, ipfsCID)` (requires `ASP_POSTMAN_ROLE`)
- **Lifecycle**: `windDown()` (blocks new deposits, withdrawals still work)
- **Views**: `ASSET()`, `SCOPE()`, `nonce()`, `currentRoot()`, `nullifierHashes()`, `admin()`, etc.
- **Loupe**: `facetAddress(selector)`, `facetAddresses()`, `facetFunctionSelectors(facet)`

---

## OIF Settlers

### ShinobiInputSettler

Manages intent creation and escrow. State machine: `None → Deposited → Claimed/Refunded`.

### ShinobiDepositOutputSettler

Fills deposit intents on pool chain. **MANDATORY** intent proof validation via `intentOracle`.

### ShinobiWithdrawalOutputSettler

Fills withdrawal intents on origin chain. **OPTIMISTIC** — no intent proof validation (ZK proof already validated on pool chain).

### Intent Data Structure

```solidity
struct ShinobiIntent {
    address user;
    uint256 nonce;
    uint256 originChainId;
    uint32 expires;
    uint32 fillDeadline;
    address fillOracle;
    uint256[2][] inputs;
    MandateOutput[] outputs;
    address intentOracle;
    bytes refundCalldata;
}
```

---

## Paymasters (ERC-4337)

Four paymasters enable gasless withdrawals. Each validates ZK proofs in `validatePaymasterUserOp` and refunds excess gas in `postOp`.

| Paymaster | Operation | Proof Signals |
|-----------|-----------|---------------|
| `WithdrawalPaymaster` | Same-chain 1:1 | 8 |
| `CrosschainWithdrawalPaymaster` | Cross-chain 1:1 + refund | 11 |
| `Withdraw2Paymaster` | Same-chain 2:1 merge | 9 |
| `CrosschainWithdraw2Paymaster` | Cross-chain 2:1 + refund | 12 |

All paymasters:
- Hold immutable `POOL` address and verifier
- Accept concrete types directly (`WithdrawData` or `CrosschainWithdrawData`)
- Use transient storage (EIP-1153) for validation-to-postOp data passing
- Validate ZK proofs independently (don't trust the bundler)
- Use self-call pattern for embedded proof validation

---

## ZK Proof Structures

### Standard Withdrawal (8 signals)
```
[0] newCommitment  [1] existingNullifierHash  [2] withdrawnValue
[3] stateRoot  [4] stateTreeDepth  [5] ASPRoot  [6] ASPTreeDepth  [7] context
```

### Cross-Chain Withdrawal (11 signals)
```
[0] newCommitment  [1] existingNullifierHash  [2] refundCommitment
[3] relayFeeBPS  [4] refundFeeBPS  [5] withdrawnValue
[6] stateRoot  [7] stateTreeDepth  [8] ASPRoot  [9] ASPTreeDepth  [10] context
```

### Withdraw2 (9 signals) — 2:1 merge
```
[0] newCommitment  [1] nullifierHash0  [2] nullifierHash1
[3] withdrawnValue  [4] stateRoot  [5] stateTreeDepth
[6] ASPRoot  [7] ASPTreeDepth  [8] context
```

### CrosschainWithdraw2 (12 signals) — 2:1 merge cross-chain
```
[0] newCommitment  [1] nullifierHash0  [2] nullifierHash1  [3] refundCommitment
[4] relayFeeBPS  [5] refundFeeBPS  [6] withdrawnValue
[7] stateRoot  [8] stateTreeDepth  [9] ASPRoot  [10] ASPTreeDepth  [11] context
```

### Ragequit (4 signals)
```
[0] commitmentHash  [1] nullifierHash  [2] value  [3] label
```

---

## Cross-Chain Flows

### Cross-Chain Withdrawal

```
User → ShinobiPool.crosschainWithdraw(data, proof)
  → Facet validates ZK proof, spends nullifier, inserts commitment
  → Relay fee paid to feeRecipient
  → Remaining ETH escrowed with IShinobiInputSettler.open()
  → Solver fills on destination chain via WithdrawalOutputSettler
  → HyperlaneOracle relays fill proof back
  → Solver claims escrowed ETH from InputSettler
```

If intent expires:
```
InputSettler → ShinobiPool.handleRefund()
  → RefundOps inserts refund commitment into Merkle tree
  → User can withdraw again with the refund commitment
```

### Cross-Chain Deposit

```
User → ShinobiCrosschainDepositEntrypoint.deposit() on origin chain
  → InputSettler escrows funds
  → Solver fills on pool chain via DepositOutputSettler
  → DepositOutputSettler → ShinobiPool.crosschainDeposit()
  → Commitment inserted into Merkle tree
  → HyperlaneOracle relays proof → Solver claims escrowed ETH
```

---

## Fee Structure

### Same-Chain Withdrawal Fees
```
relayFee       = withdrawnValue × relayFeeBPS / 10000
recipientAmount = withdrawnValue - relayFee
```

### Cross-Chain Withdrawal Fees
```
relayFee     = withdrawnValue × relayFeeBPS / 10000
escrowAmount = withdrawnValue - relayFee
solverFee    = withdrawnValue × solverFeeBPS / 10000
netAmount    = escrowAmount - solverFee
```

### Deposit Fees
```
solverFee        = totalPaid × solverFeeBPS / 10000
netDepositAmount = totalPaid - solverFee
```

---

## Deployed Contract Addresses (Testnet)

### Arbitrum Sepolia (Pool Chain - 421614)

| Contract | Address |
|----------|---------|
| Entrypoint (legacy) | `0xa6f7fdF6d62f3a56B4469046C7927f4cb0c67595` |
| ETH Pool (legacy) | `0xF400070885d773ef29C1e7c04eDffd637C22584B` |
| Input Settler | `0x4385eebaC4Eab0bc93E6D43270908da07e4b3178` |
| Deposit Output Settler | `0x843B07421385282EEE4FE1135DD1A63c1184aD71` |
| Hyperlane Oracle | `0x246e0E2e416a9B06Cd806292f6a4eCb269cfA7CA` |

**Verifiers**:
| Verifier | Address |
|----------|---------|
| Withdrawal | `0x1A6ffA02c307A1856D5ffA9432545012eb929aad` |
| Commitment | `0x020507eAb83152E19c5B8A3234385d4423Ed3185` |
| Cross-Chain Withdrawal | `0x4551bb04e9218b38902E6a489906BAB4816e01b2` |
| Withdraw2 | `0x11Ce8937b38487CDeec8C5c4a08792b58dCd41d6` |
| CrossChainWithdraw2 | `0xe88911836140a2Aa2eD2560cb845003487137cB7` |

**Paymasters**:
| Paymaster | Address |
|-----------|---------|
| Withdrawal | `0x52Ac5611230658aAf42e183D28Fab191C0bdff98` |
| Cross-Chain | `0x522d4Bb38F89D793D2996096592c01CB053eD3a5` |
| Withdraw2 | `0x4E4a1E964baDCBB6Be5f14b324238C24E69dD56D` |
| CrossChainWithdraw2 | `0x82eaeF17B861Bc7E3cBeC50Ce1fF39B58453ef27` |

### Base Sepolia (Origin Chain - 84532)

| Contract | Address |
|----------|---------|
| Deposit Entrypoint | `0x655973cd82614e7e37188d1e5b893973339842f1` |
| Input Settler | `0xCd7722864E24bF241272dF1a7237F22bCb772db2` |
| Withdrawal Output Settler | `0x3c10FcD909B932AFb183b03377D1aFdc9F097931` |
| Hyperlane Oracle | `0x9bd18887d5a37a5851aEB89E0e68E665D628Dd7B` |

---

## Deployment Scripts

### Pool Chain Pipeline (`script/pool/`)

| Step | Script | Purpose |
|------|--------|---------|
| 01 | `01_Deploy_Verifiers.s.sol` | Deploy 5 ZK verifiers |
| 02–08 | `02–08_Deploy_*Action.s.sol` | Deploy 7 action facets (one per script) |
| 09 | `09_Deploy_ShinobiPool.s.sol` | Deploy ShinobiPool proxy |
| 10 | `10_Deploy_Settlers.s.sol` | Deploy InputSettler, HyperlaneOracle, DepositOutputSettler |
| 11 | `11_Setup_ShinobiPool.s.sol` | Configure pool (asset config, fees, settlers) |
| 12 | `12_Deploy_Paymasters.s.sol` | Deploy 4 paymasters |
| 13 | `13_Setup_WithdrawalChains.s.sol` | Configure withdrawal chain (per origin) |
| 14 | `14_Deploy_Timelock.s.sol` | Deploy TimelockController + bootstrap admin transfer |

### Origin Chain Pipeline (`script/chains/`)

| Script | Purpose |
|--------|---------|
| `AddChain_01_DeployOriginContracts.s.sol` | Deploy Oracle, DepositEntrypoint, InputSettler, WithdrawalOutputSettler |
| `AddChain_02_ConfigurePoolChain.s.sol` | Configure DepositOutputSettler to accept from origin |
| `AddChain_03_ConfigureOriginChain.s.sol` | Configure origin entrypoint, oracles, fees, Hyperlane |

### Other

| Path | Purpose |
|------|---------|
| `script/config/` | ChainConfig, DeploymentWriter, pool/origin JSON configs |
| `script/utils/WithdrawPaymasterDeposits.s.sol` | Withdraw ERC-4337 EntryPoint deposits |

---

## Security Considerations

### ZK Proof Validation
- Context binding: `keccak256(abi.encode(data), scope) % SNARK_FIELD`
- State root in 64-entry circular buffer
- ASP root must be latest
- Nullifiers checked for double-spend
- Tree depths bounded at 32

### Balance Invariant
All withdrawal facets verify `balanceBefore - address(this).balance <= withdrawnValue`.

### Fee Bounds
- Relay fee: `0 < relayFeeBPS <= maxRelayFeeBPS`
- Solver fee: `solverFeeBPS <= maxSolverFeeBPS`
- Refund fee: `0 < refundFeeBPS <= maxRefundFeeBPS`

### Reentrancy
EIP-1153 transient storage guard (~100 gas vs ~5000 for SSTORE).

### Oracle Security
| Oracle | Direction | Purpose | Required For |
|--------|-----------|---------|--------------|
| `fillOracle` | Dest → Origin | Proves fill happened | All intents |
| `intentOracle` | Origin → Dest | Proves intent is legitimate | Deposits only |

---

## Environment Variables

```bash
PRIVATE_KEY=           # Deployer private key (0x prefixed)
ETHERSCAN_API_KEY=     # For contract verification
POOL_KEY=              # Pool config key (e.g., "arbitrum-sepolia")
```

---

## Common Patterns

### Context Validation

```solidity
// Facets pass abi.encode(data) to PoolOps
PoolOps.validateProofContext(s, abi.encode(data), proof.context());

// PoolOps computes:
uint256 expectedContext = uint256(
    keccak256(abi.encode(withdrawalData, s.scope))
) % Constants.SNARK_SCALAR_FIELD;
```

### Transient Storage (EIP-1153)

```solidity
// Store in validation (paymaster)
assembly {
    tstore(0, withdrawnValue)
    tstore(1, relayFeeBPS)
    tstore(2, withdrawalRecipient)
}

// Read in postOp
uint256 withdrawnValue;
assembly { withdrawnValue := tload(0) }
```

---

## Key Debugging Tips

1. **"InvalidOrderStatus"**: Check order state machine — likely already claimed/refunded
2. **"UnauthorizedCaller"**: Only entrypoint/pool can call `open()` on InputSettler
3. **"IntentNotProven"**: Oracle hasn't attested to intent — check HyperlaneOracle
4. **"FillOracleMismatch"**: Intent uses different fillOracle than configured
5. **"ContextMismatch"**: ZK proof context doesn't match `keccak256(abi.encode(data), scope)`
6. **"UnknownStateRoot"**: State root not in recent 64-entry root history
7. **"DeadlinePassed"**: Fill attempted after fillDeadline
8. **"ExpiryNotReached"**: Refund attempted before expires timestamp
9. **"FunctionNotFound"**: Selector not registered in pool — check facet registration
10. **"OnlyAdmin"**: Caller is not the pool admin

---

## References

- [Privacy Pools Paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4563364)
- [Open Intent Framework](https://github.com/open-intent-framework/oif)
- [ERC-4337 Account Abstraction](https://eips.ethereum.org/EIPS/eip-4337)
- [ERC-8153 Diamond Standard](https://eips.ethereum.org/EIPS/eip-8153)
- [Groth16 SNARKs](https://eprint.iacr.org/2016/260.pdf)
- [Hyperlane Documentation](https://docs.hyperlane.xyz/)

---

*Built for Ethereum privacy across chains*
