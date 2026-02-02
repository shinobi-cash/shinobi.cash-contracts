# CLAUDE.md - Shinobi.cash Contracts

This file provides comprehensive guidance to Claude Code when working with the Shinobi.cash smart contracts repository.

## Project Overview

Shinobi.cash Contracts is a cross-chain privacy protocol enabling users to deposit on one blockchain and withdraw privately on another. The system combines:
- **Zero-knowledge proofs** (Groth16 SNARKs) for privacy
- **Privacy Pools** with Merkle tree commitments and nullifiers
- **Open Intent Framework (OIF)** for cross-chain settlement
- **ERC-4337 Account Abstraction** for gasless withdrawals

> **WARNING**: This project is under active development and has NOT been audited. Testnet only.

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
forge script script/XX_Script.s.sol --rpc-url <network> --broadcast

# Deploy to Testnet (example)
forge script script/02_DeployEntrypoint.s.sol \
  --rpc-url arbitrum-sepolia \
  --broadcast \
  --verify
```

---

## Directory Structure

```
shinobi.cash-contracts/
├── src/
│   ├── core/                           # Core privacy pool contracts
│   │   ├── ShinobiCashPool.sol         # Abstract pool with cross-chain support
│   │   ├── ShinobiCashEntrypoint.sol   # Main orchestrator (pool chain)
│   │   ├── ShinobiCrosschainDepositEntrypoint.sol  # Deposit interface (origin chain)
│   │   ├── ShinobiCashCrosschainState.sol          # Cross-chain state management
│   │   ├── implementations/
│   │   │   └── ShinobiCashPoolSimple.sol           # Native ETH pool
│   │   ├── interfaces/                  # Contract interfaces
│   │   ├── libraries/
│   │   │   └── CrossChainProofLib.sol   # 9-signal proof extraction
│   │   └── verifiers/
│   │       └── CrossChainWithdrawalVerifier.sol    # Groth16 verifier
│   ├── oif/                            # Open Intent Framework settlers
│   │   ├── ShinobiInputSettler.sol     # Escrow & settlement (origin)
│   │   ├── ShinobiDepositOutputSettler.sol         # Deposit fills (destination)
│   │   ├── ShinobiWithdrawalOutputSettler.sol      # Withdrawal fills (destination)
│   │   ├── BaseShinobiOutputSettler.sol            # Shared output settler logic
│   │   ├── interfaces/
│   │   └── libraries/
│   │       ├── ShinobiIntentType.sol   # Intent struct definition
│   │       └── ShinobiIntentLib.sol    # Intent utilities
│   ├── paymaster/                      # ERC-4337 paymasters
│   │   ├── SimpleShinobiCashPoolPaymaster.sol      # Standard 1:1 withdrawal paymaster
│   │   ├── CrossChainWithdrawalPaymaster.sol       # Cross-chain 1:1 withdrawal paymaster
│   │   ├── Withdraw2Paymaster.sol                  # Same-chain 2:1 merge paymaster
│   │   └── CrosschainWithdraw2Paymaster.sol        # Cross-chain 2:1 merge paymaster
│   └── mocks/
│       └── MockOracle.sol              # Testing oracle (always returns true)
├── script/                             # Foundry deployment scripts
│   ├── 00_DeployMockOracles.s.sol
│   ├── 01_DeployVerifiers.s.sol
│   ├── 02_DeployEntrypoint.s.sol
│   ├── 03_DeployPrivacyPool.s.sol
│   ├── 04a_DeployInputSettlerArbitrum.s.sol
│   ├── 04b_DeployDepositOutputSettlerArbitrum.s.sol
│   ├── 04c_DeployDepositEntrypoint.s.sol
│   ├── 04d_DeployInputSettlerBase.s.sol
│   ├── 04e_DeployWithdrawalOutputSettlerBase.s.sol
│   ├── 05_SetupEntrypoint.s.sol
│   ├── 06_SetupDepositEntrypoint.s.sol
│   └── 07_DeployPaymasters.s.sol
├── lib/                                # Git submodule dependencies
│   ├── account-abstraction/            # ERC-4337 implementation
│   ├── openzeppelin-contracts/         # Standard OZ contracts
│   ├── privacy-pools-core/             # Base privacy pool implementation
│   ├── oif/                            # OIF specification
│   ├── oif-contracts/                  # OIF implementation
│   └── forge-std/                      # Foundry standard library
├── test/                               # Tests (currently uses external framework)
├── foundry.toml                        # Foundry configuration
├── package.json                        # npm dependencies
└── remappings.txt                      # Import path mappings
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

[rpc_endpoints]
base-sepolia = "https://sepolia.base.org"
arbitrum-sepolia = "https://arb-sepolia.g.alchemy.com/v2/..."
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
interfaces/=lib/privacy-pools-core/packages/contracts/src/interfaces/
contracts/=lib/privacy-pools-core/packages/contracts/src/
oif/=lib/oif/solidity/src/
oif-contracts/=lib/oif-contracts/src/
lean-imt/=node_modules/@zk-kit/lean-imt.sol/
poseidon-solidity/=node_modules/poseidon-solidity/
```

---

## Architecture Deep Dive

### Contract Inheritance Hierarchy

```
                    ┌─────────────────────────────────┐
                    │     privacy-pools-core          │
                    │   ┌───────────────────────┐     │
                    │   │     PrivacyPool       │     │
                    │   │  (base implementation)│     │
                    │   └───────────┬───────────┘     │
                    └───────────────┼─────────────────┘
                                    │ extends
                    ┌───────────────▼───────────────┐
                    │      ShinobiCashPool          │
                    │  (abstract, cross-chain)      │
                    │  + crosschainWithdraw()       │
                    │  + handleRefund()             │
                    └───────────────┬───────────────┘
                                    │ extends
                    ┌───────────────▼───────────────┐
                    │   ShinobiCashPoolSimple       │
                    │   (native ETH implementation) │
                    │  + _pull() / _push()          │
                    └───────────────────────────────┘

                    ┌─────────────────────────────────┐
                    │     privacy-pools-core          │
                    │   ┌───────────────────────┐     │
                    │   │      Entrypoint       │     │
                    │   │   (base entrypoint)   │     │
                    │   └───────────┬───────────┘     │
                    └───────────────┼─────────────────┘
                                    │ extends
                    ┌───────────────▼───────────────┐
                    │    ShinobiCashEntrypoint      │
                    │  + ShinobiCashCrosschainState │
                    │  + crosschainWithdrawal()     │
                    │  + crosschainDeposit()        │
                    │  + handleRefund()             │
                    └───────────────────────────────┘
```

---

## Core Contracts

### 1. ShinobiCashPool (Abstract)

**Purpose**: Extended PrivacyPool with cross-chain withdrawal support.

**Location**: `src/core/ShinobiCashPool.sol`

**Key Features**:
- Inherits from `PrivacyPool` (privacy-pools-core)
- Validates 9-signal ZK proofs for cross-chain withdrawals
- Handles refund commitment insertion for failed intents

**State Variables**:
```solidity
ICrossChainWithdrawalProofVerifier public immutable CROSS_CHAIN_WITHDRAWAL_VERIFIER;
```

**Key Functions**:

```solidity
/// Process cross-chain withdrawal with enhanced 9-signal proof
function crosschainWithdraw(
    Withdrawal memory _withdrawal,
    CrossChainProofLib.CrossChainWithdrawProof memory _proof
) external

/// Handle refund for failed cross-chain withdrawal
/// Inserts refund commitment into merkle tree
function handleRefund(
    uint256 _refundCommitmentHash,
    uint256 _amount
) external payable onlyEntrypoint
```

**Cross-Chain Withdrawal Flow**:
```
1. Validate processooor (msg.sender)
2. Validate context matches withdrawal data + SCOPE
3. Validate tree depths within bounds
4. Validate state root is known
5. Validate ASP root is latest
6. Verify Groth16 proof
7. Spend nullifier
8. Insert new commitment
9. Transfer withdrawn value to processooor
10. Emit CrosschainWithdrawn event
```

---

### 2. ShinobiCashEntrypoint

**Purpose**: Central orchestrator for cross-chain operations on the pool chain.

**Location**: `src/core/ShinobiCashEntrypoint.sol`

**Inheritance**: `Entrypoint`, `ShinobiCashCrosschainState`, `IShinobiCashCrossChainHandler`

**Key State**:
```solidity
// Settler addresses
address public withdrawalInputSettler;    // For withdrawal intents
address public depositOutputSettler;       // For deposit fills

// Per-chain destination configuration
mapping(uint256 => WithdrawalChainConfig) public withdrawalChainConfig;

// Precommitment replay prevention
mapping(uint256 => bool) public usedPrecommitments;

struct WithdrawalChainConfig {
    bool isConfigured;           // Whether this destination is configured
    uint32 fillDeadline;         // Default fill deadline (relative to block.timestamp)
    uint32 expiry;               // Default expiry (relative to block.timestamp)
    address withdrawalOutputSettler;  // ShinobiWithdrawalOutputSettler on destination
    address withdrawalFillOracle;     // Output Oracle on destination chain
    address fillOracle;               // Fill oracle for validating fills (dest → origin)
}
```

**Key Functions**:

```solidity
/// Main entry point for cross-chain withdrawals
/// Validates ZK proof and creates OIF intent
function crosschainWithdrawal(
    IPrivacyPool.Withdrawal calldata _withdrawal,
    CrossChainProofLib.CrossChainWithdrawProof calldata _proof,
    uint256 _scope
) external nonReentrant

/// Handle verified cross-chain deposit
/// Called by ShinobiDepositOutputSettler after oracle validation
function crosschainDeposit(
    address _depositor,
    uint256 _amount,
    uint256 _precommitment
) external payable nonReentrant onlyDepositOutputSettler

/// Handle refund for failed withdrawal
/// Called by ShinobiInputSettler when intent expires
function handleRefund(
    uint256 _refundCommitmentHash,
    uint256 _amount,
    uint256 _scope
) external payable onlyWithdrawalInputSettler

/// Configure destination chain for cross-chain withdrawals
function setWithdrawalChainConfig(
    uint256 _chainId,
    address _outputSettler,
    address _outputOracle,
    address _fillOracle,
    uint32 _fillDeadline,
    uint32 _expiry
) external onlyRole(_OWNER_ROLE)
```

**Cross-Chain Withdrawal Flow**:
```
1. Validate withdrawalInputSettler is configured
2. Validate withdrawn amount > 0
3. Validate processooor is this entrypoint
4. Fetch pool by scope, validate exists
5. Decode CrossChainRelayData from withdrawal.data
6. Validate destination chain is configured
7. Validate relay fee <= max
8. Execute pool.crosschainWithdraw() (validates ZK proof)
9. Calculate fees (relay + solver)
10. Create OIF intent with configured destination settings
11. Transfer relay fee to feeRecipient
12. Open intent on ShinobiInputSettler (escrows funds)
13. Emit CrossChainWithdrawalIntentRelayed event
```

---

### 3. ShinobiCrosschainDepositEntrypoint

**Purpose**: Lightweight deposit interface on origin chains (e.g., Base Sepolia).

**Location**: `src/core/ShinobiCrosschainDepositEntrypoint.sol`

**Key State**:
```solidity
address public inputSettler;              // ShinobiInputSettler address
bool private inputSettlerSet;             // Flag to ensure inputSettler only set once
uint32 public defaultFillDeadline;        // Default: 1 hour
uint32 public defaultExpiry;              // Default: 24 hours
address public fillOracle;                // Fill validation oracle
address public intentOracle;              // Intent proof oracle
uint256 public destinationChainId;
address public destinationEntrypoint;
address public destinationOutputSettler;
address public destinationOracle;
uint256 public minimumDepositAmount;      // Default: 0.01 ETH
uint256 public defaultSolverFeeBPS;       // Default: 500 (5%)
uint256 public maxSolverFeeBPS;           // Default: 1000 (10%)
uint256 public nonce;                     // Global nonce for unique order IDs
mapping(address => address) public assetToPool;  // Asset to destination pool
```

**Key Functions**:

```solidity
/// Deposit with default solver fee
function deposit(uint256 precommitment) external payable nonReentrant

/// Deposit with custom solver fee
function depositWithCustomFee(
    uint256 precommitment,
    uint256 customSolverFeeBPS
) external payable nonReentrant

/// Request refund for expired deposit
function refund(ShinobiIntent calldata intent) external nonReentrant
```

**Deposit Flow**:
```
1. Validate amount > 0 and >= minimumDepositAmount
2. Validate destination chain is configured
3. Validate asset pool is configured
4. Calculate solver fee: (totalPaid * solverFeeBPS) / 10000
5. Calculate net deposit: totalPaid - solverFee
6. Construct ShinobiIntent:
   - user: msg.sender (verified depositor)
   - intentOracle: configured oracle (for validation)
   - output.call: crosschainDeposit(depositor, amount, precommitment)
7. Call inputSettler.open{value: totalPaid}(intent)
8. Emit CrossChainDepositIntent event
```

---

## OIF Settlers

### Intent Data Structure

**Location**: `src/oif/libraries/ShinobiIntentType.sol`

```solidity
struct ShinobiIntent {
    // Base OIF StandardOrder Fields
    address user;           // Intent creator (verified on origin)
    uint256 nonce;          // Unique identifier component
    uint256 originChainId;  // Chain where intent was created
    uint32 expires;         // Expiry timestamp for refunds
    uint32 fillDeadline;    // Deadline for filling
    address fillOracle;     // Oracle for fill proof validation (dest → origin)
    uint256[2][] inputs;    // Input tokens [tokenId, amount][]
    MandateOutput[] outputs;// Outputs to fill on destination

    // Shinobi Extensions
    address intentOracle;   // Oracle for intent proof validation (origin → dest)
    bytes refundCalldata;   // Custom refund logic (empty = simple ETH transfer)
}
```

---

### 4. ShinobiInputSettler

**Purpose**: Manages intent creation and escrow on origin chain.

**Location**: `src/oif/ShinobiInputSettler.sol`

**Key State**:
```solidity
address public immutable entrypoint;  // Only caller for open()
mapping(bytes32 => OrderStatus) public orderStatus;

enum OrderStatus {
    None,       // Order doesn't exist
    Deposited,  // Funds escrowed, awaiting fill or expiry
    Claimed,    // Solver filled and claimed
    Refunded    // Intent expired and refunded
}
```

**Key Functions**:

```solidity
/// Create intent and escrow funds (ONLY entrypoint can call)
function open(ShinobiIntent calldata intent) external payable

/// Finalize after solver fills (validates via oracle)
function finalise(
    ShinobiIntent calldata intent,
    SolveParams[] calldata solveParams,
    bytes32 destination
) external

/// Refund expired intent (permissionless, funds go to intent.user)
function refund(ShinobiIntent calldata intent) external

/// Compute unique order identifier
function orderIdentifier(ShinobiIntent memory intent) public pure returns (bytes32)
```

**Settlement State Machine**:
```
                              ┌─────────────┐
                              │    None     │
                              └──────┬──────┘
                                     │ open()
                              ┌──────▼──────┐
                              │  Deposited  │
                              └──────┬──────┘
                          ┌──────────┴──────────┐
                          │                     │
                  finalise()                 refund()
                          │                     │
                   ┌──────▼──────┐       ┌──────▼──────┐
                   │   Claimed   │       │  Refunded   │
                   └─────────────┘       └─────────────┘
```

**Oracle Validation (in finalise)**:
```
For each output:
1. Check fill timestamp <= fillDeadline
2. Build payloadHash = keccak256(solver | orderId | timestamp | output)
3. Pack into proofSeries: [chainId, oracle, settler, payloadHash]
4. Call fillOracle.efficientRequireProven(proofSeries)
```

---

### 5. ShinobiDepositOutputSettler

**Purpose**: Handles fills for deposit intents on pool chain (destination).

**Location**: `src/oif/ShinobiDepositOutputSettler.sol`

**Key Difference**: **MANDATORY** intent proof validation via configured intentOracle.

**Why**: Deposits need to verify the depositor address came from a legitimate user on the origin chain. Without this, an attacker could create fake intents with any depositor address.

```solidity
address public immutable intentOracle;  // MUST be used for all deposits

function fill(ShinobiIntent calldata intent) external payable nonReentrant {
    // 1. Validate deposits have exactly one output
    if (intent.outputs.length != 1) revert InvalidOutput();

    // 2. Validate correct destination chain
    if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

    // 3. Validate fill deadline
    if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

    // 4. CRITICAL: Validate intent uses configured oracle
    if (intent.intentOracle != intentOracle) revert IntentOracleMismatch();

    // 5. Compute unique order identifier
    bytes32 orderId = intent.orderIdentifier();

    // 6. CRITICAL: Validate intent proof via oracle
    if (!IInputOracle(intentOracle).isProven(
        intent.originChainId,
        bytes32(uint256(uint160(intentOracle))),
        bytes32(uint256(uint160(address(this)))),
        orderId
    )) revert IntentNotProven();

    // 7. Fill output with callback to crosschainDeposit()
    _fillOutput(orderId, intent.outputs[0], msg.sender);
}
```

---

### 6. ShinobiWithdrawalOutputSettler

**Purpose**: Handles fills for withdrawal intents on user's chain (destination).

**Location**: `src/oif/ShinobiWithdrawalOutputSettler.sol`

**Key Difference**: **OPTIMISTIC** settlement - NO intent proof validation.

**Why**: ZK proof on origin chain already validated the withdrawer's credentials. The privacy pool verified nullifier and commitment ownership. Intent was created by trusted ShinobiCashEntrypoint.

```solidity
address public immutable fillOracle;  // Validated for consistency

function fill(ShinobiIntent calldata intent) external payable nonReentrant {
    // 1. Validate has outputs
    if (intent.outputs.length == 0) revert InvalidOutput();

    // 2. Validate correct destination chain
    if (intent.outputs[0].chainId != block.chainid) revert InvalidChain();

    // 3. Validate fill deadline
    if (block.timestamp > intent.fillDeadline) revert FillDeadlinePassed();

    // 4. Validate fillOracle for consistency (ensures InputSettler can validate)
    if (intent.fillOracle != fillOracle) revert FillOracleMismatch();

    // 5. Compute unique order identifier
    bytes32 orderId = intent.orderIdentifier();

    // NO intentOracle validation - ZK proof already validated on origin chain

    // 6. Fill each output with simple ETH transfer
    for (uint256 i = 0; i < intent.outputs.length; i++) {
        _fillOutput(orderId, intent.outputs[i], msg.sender);
    }
}
```

---

## Paymasters (ERC-4337)

### 7. SimpleShinobiCashPoolPaymaster

**Purpose**: Sponsors gas for standard privacy pool withdrawal UserOperations.

**Location**: `src/paymaster/SimpleShinobiCashPoolPaymaster.sol`

**Key Features**:
- Embedded ZK proof validation (doesn't trust external calls)
- Economics validation (relay fee covers gas)
- Transient storage (EIP-1153) for gas efficiency
- PostOp refunds excess fees to user

**Constants**:
```solidity
uint256 public constant POST_OP_GAS_LIMIT = 100_000;
uint256 public constant MIN_CALL_GAS_LIMIT = 550_000;
uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 400_000;
```

**Validation Flow**:
```
1. Check expectedSmartAccount is configured
2. Verify UserOp from expected smart account
3. Ensure no initCode (account already deployed)
4. Check gas limits are sufficient:
   - postOp gas limit >= POST_OP_GAS_LIMIT (100000)
   - call gas limit >= MIN_CALL_GAS_LIMIT (550000)
   - paymaster verification gas >= MIN_PAYMASTER_VERIFICATION_GAS (400000)
5. Extract SimpleAccount.execute(target, value, data)
6. Call internal relay() to validate withdrawal:
   a. Verify processooor is SHINOBI_CASH_ENTRYPOINT
   b. Decode RelayData, verify feeRecipient is this paymaster
   c. Verify scope matches ETH_CASH_POOL.SCOPE()
   d. Validate ZK proof (context, tree depths, roots, nullifier, Groth16)
   e. Store values in transient storage
7. Validate economics: expectedFee >= maxCost
8. Return context with userOpHash, recipient, expectedFee
```

**Embedded Relay Method** (external but only callable by self):
```solidity
/// Called by paymaster itself to validate withdrawal without execution
/// External function that checks msg.sender == address(this)
function relay(
    IPrivacyPool.Withdrawal calldata withdrawal,
    ProofLib.WithdrawProof calldata proof,
    uint256 scope
) external {
    if (msg.sender != address(this)) revert UnauthorizedCaller();

    // Validate processooor, feeRecipient, scope
    // Verify ZK proof via _validateWithdrawCall()
    // Store in transient storage for economic checks
    assembly {
        tstore(0, withdrawnValue)
        tstore(1, relayFeeBPS)
        tstore(2, withdrawalRecipient)
    }
}
```

---

### 8. CrossChainWithdrawalPaymaster

**Purpose**: Sponsors gas for cross-chain withdrawal UserOperations.

**Location**: `src/paymaster/CrossChainWithdrawalPaymaster.sol`

Similar to SimpleShinobiCashPoolPaymaster but validates 9-signal cross-chain proofs.

---

### 9. Withdraw2Paymaster

**Purpose**: Sponsors gas for Withdraw2 (2:1 JoinSplit) same-chain UserOperations.

**Location**: `src/paymaster/Withdraw2Paymaster.sol`

**Key Differences from Standard Paymaster**:
- Validates 9-signal Withdraw2 proof (2 nullifiers)
- Higher gas limits (~50% more for 2 input validation)
- Uses `IWithdraw2Verifier` interface

**Constants**:
```solidity
uint256 public constant POST_OP_GAS_LIMIT = 150_000;
uint256 public constant MIN_CALL_GAS_LIMIT = 900_000;
uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 675_000;
```

---

### 10. CrosschainWithdraw2Paymaster

**Purpose**: Sponsors gas for CrosschainWithdraw2 (2:1 JoinSplit) cross-chain UserOperations.

**Location**: `src/paymaster/CrosschainWithdraw2Paymaster.sol`

**Key Differences**:
- Validates 10-signal proof (2 nullifiers + refund commitment)
- Highest gas limits (~75% more than standard)
- Uses `ICrosschainWithdraw2Verifier` interface

**Constants**:
```solidity
uint256 public constant POST_OP_GAS_LIMIT = 150_000;
uint256 public constant MIN_CALL_GAS_LIMIT = 1_050_000;
uint256 public constant MIN_PAYMASTER_VERIFICATION_GAS = 750_000;
```

---

## ZK Proof Structures

### Standard Withdrawal Proof (8 signals)

```solidity
struct WithdrawProof {
    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;
    uint256[8] pubSignals;
    // [0] newCommitmentHash
    // [1] existingNullifierHash
    // [2] withdrawnValue
    // [3] stateRoot
    // [4] stateTreeDepth
    // [5] ASPRoot
    // [6] ASPTreeDepth
    // [7] context
}
```

### Cross-Chain Withdrawal Proof (9 signals)

```solidity
struct CrossChainWithdrawProof {
    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;
    uint256[9] pubSignals;
    // [0] newCommitmentHash
    // [1] existingNullifierHash
    // [2] refundCommitmentHash   ← NEW for cross-chain
    // [3] withdrawnValue
    // [4] stateRoot
    // [5] stateTreeDepth
    // [6] ASPRoot
    // [7] ASPTreeDepth
    // [8] context
}
```

The 9th signal (`refundCommitmentHash`) enables recovery if the cross-chain intent fails - the escrowed funds return to the pool as a new commitment.

### Withdraw2 Proof (9 signals) - 2:1 JoinSplit

**Purpose**: Combines 2 input notes into 1 change output + withdrawal amount.

```solidity
struct Withdraw2Proof {
    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;
    uint256[9] pubSignals;
    // [0] newCommitmentHash       ← Single change output
    // [1] nullifierHash0          ← First input nullifier
    // [2] nullifierHash1          ← Second input nullifier
    // [3] withdrawnValue
    // [4] stateRoot
    // [5] stateTreeDepth
    // [6] ASPRoot
    // [7] ASPTreeDepth
    // [8] context
}
```

**Chain Inheritance**: The larger `depositIndex` determines which chain continues. The circuit uses `labelSelector` (0 or 1) to select output label.

### CrosschainWithdraw2 Proof (10 signals) - 2:1 JoinSplit Cross-Chain

```solidity
struct CrosschainWithdraw2Proof {
    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;
    uint256[10] pubSignals;
    // [0] newCommitmentHash       ← Single change output
    // [1] nullifierHash0          ← First input nullifier
    // [2] nullifierHash1          ← Second input nullifier
    // [3] refundCommitmentHash    ← For cross-chain recovery
    // [4] withdrawnValue
    // [5] stateRoot
    // [6] stateTreeDepth
    // [7] ASPRoot
    // [8] ASPTreeDepth
    // [9] context
}
```

---

## Cross-Chain Flow Diagrams

### Cross-Chain Withdrawal Flow

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     ARBITRUM SEPOLIA (Pool Chain)                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌──────────────┐         ┌─────────────────────┐                         │
│   │  User/Smart  │         │ ShinobiCashEntrypoint│                         │
│   │   Account    │         └──────────┬──────────┘                         │
│   └──────┬───────┘                    │                                    │
│          │                            │                                    │
│          │ 1. crosschainWithdrawal()  │                                    │
│          │    (ZK proof + destination)│                                    │
│          │ ──────────────────────────►│                                    │
│          │                            │                                    │
│          │                    ┌───────▼───────┐                            │
│          │                    │ShinobiCashPool │                            │
│          │                    │ (validates ZK) │                            │
│          │                    └───────┬───────┘                            │
│          │                            │                                    │
│          │                    ┌───────▼────────────┐                       │
│          │                    │ ShinobiInputSettler│                       │
│          │                    │  (escrows ETH)     │                       │
│          │                    └───────┬────────────┘                       │
│          │                            │                                    │
│          │ 2. Relay fee paid to       │                                    │
│          │    paymaster/relayer       │                                    │
│          │ ◄──────────────────────────┘                                    │
│                                                                            │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │
                                   │ 3. Solver monitors intent
                                   │    via indexer/oracle
                                   ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                       BASE SEPOLIA (User Chain)                            │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌─────────────┐            ┌──────────────────────────┐                  │
│   │   Solver    │            │ShinobiWithdrawalOutputSettler │              │
│   └──────┬──────┘            └───────────┬──────────────┘                  │
│          │                               │                                 │
│          │ 4. fill() with ETH            │                                 │
│          │ ─────────────────────────────►│                                 │
│          │                               │                                 │
│          │                       ┌───────▼───────┐                         │
│          │                       │ User Recipient│                         │
│          │                       │  (receives ETH)│                         │
│          │                       └───────────────┘                         │
│                                                                            │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │
                                   │ 5. Fill proof relayed
                                   │    via oracle
                                   ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     ARBITRUM SEPOLIA (Pool Chain)                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌─────────────┐            ┌────────────────────┐                        │
│   │   Solver    │            │ShinobiInputSettler │                        │
│   └──────┬──────┘            └──────────┬─────────┘                        │
│          │                              │                                  │
│          │ 6. finalise()                │                                  │
│          │    (proves fill via oracle)  │                                  │
│          │ ────────────────────────────►│                                  │
│          │                              │                                  │
│          │ 7. Escrowed ETH released     │                                  │
│          │ ◄────────────────────────────┘                                  │
│          │    to solver                                                    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Cross-Chain Deposit Flow

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       BASE SEPOLIA (Origin Chain)                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌─────────────┐         ┌─────────────────────────────┐                  │
│   │    User     │         │ShinobiCrosschainDepositEntrypoint│             │
│   └──────┬──────┘         └──────────────┬──────────────┘                  │
│          │                               │                                 │
│          │ 1. deposit(precommitment)     │                                 │
│          │    + ETH                      │                                 │
│          │ ─────────────────────────────►│                                 │
│          │                               │                                 │
│          │                       ┌───────▼────────────┐                    │
│          │                       │ShinobiInputSettler │                    │
│          │                       │  (escrows ETH)     │                    │
│          │                       └────────────────────┘                    │
│                                                                            │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │
                                   │ 2. Solver monitors intent
                                   │    + intent proof via oracle
                                   ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     ARBITRUM SEPOLIA (Pool Chain)                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌─────────────┐       ┌────────────────────────────┐                     │
│   │   Solver    │       │ShinobiDepositOutputSettler │                     │
│   └──────┬──────┘       └─────────────┬──────────────┘                     │
│          │                            │                                    │
│          │ 3. fill() with ETH         │                                    │
│          │    (validates intentOracle)│                                    │
│          │ ──────────────────────────►│                                    │
│          │                            │                                    │
│          │                    ┌───────▼───────────────┐                    │
│          │                    │ShinobiCashEntrypoint  │                    │
│          │                    │ crosschainDeposit()   │                    │
│          │                    └───────┬───────────────┘                    │
│          │                            │                                    │
│          │                    ┌───────▼───────┐                            │
│          │                    │ShinobiCashPool│                            │
│          │                    │(insert commit)│                            │
│          │                    └───────────────┘                            │
│                                                                            │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │
                                   │ 4. Fill proof relayed
                                   │    via oracle
                                   ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                       BASE SEPOLIA (Origin Chain)                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌─────────────┐            ┌────────────────────┐                        │
│   │   Solver    │            │ShinobiInputSettler │                        │
│   └──────┬──────┘            └──────────┬─────────┘                        │
│          │                              │                                  │
│          │ 5. finalise()                │                                  │
│          │ ────────────────────────────►│                                  │
│          │                              │                                  │
│          │ 6. Escrowed ETH released     │                                  │
│          │ ◄────────────────────────────┘                                  │
│          │    to solver                                                    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Scripts

Scripts are numbered for sequential execution:

| Script | Purpose | Chain |
|--------|---------|-------|
| `00_DeployMockOracles.s.sol` | Deploy mock oracles (testing only) | Any |
| `01_DeployVerifiers.s.sol` | Deploy ZK verifiers (standard + cross-chain) | Pool |
| `02_DeployEntrypoint.s.sol` | Deploy ShinobiCashEntrypoint (UUPS proxy) | Pool |
| `03_DeployPrivacyPool.s.sol` | Deploy ShinobiCashPoolSimple | Pool |
| `04a_DeployInputSettlerArbitrum.s.sol` | Deploy input settler for withdrawals | Pool |
| `04b_DeployDepositOutputSettlerArbitrum.s.sol` | Deploy deposit output settler | Pool |
| `04c_DeployDepositEntrypoint.s.sol` | Deploy deposit entrypoint | Origin |
| `04d_DeployInputSettlerBase.s.sol` | Deploy input settler for deposits | Origin |
| `04e_DeployWithdrawalOutputSettlerBase.s.sol` | Deploy withdrawal output settler | Origin |
| `05_SetupEntrypoint.s.sol` | Configure entrypoint (assets, fees, pools) | Pool |
| `06_SetupDepositEntrypoint.s.sol` | Configure deposit entrypoint | Origin |
| `07_DeployPaymasters.s.sol` | Deploy ERC-4337 paymasters | Pool |

---

## Fee Structure

### Withdrawal Fees

```solidity
struct CrossChainRelayData {
    bytes32 encodedDestination;  // chainId + recipient
    address feeRecipient;        // Receives relay fee
    uint256 relayFeeBPS;         // Basis points (e.g., 1500 = 15%)
    uint256 solverFeeBPS;        // Basis points (e.g., 500 = 5%)
}
```

**Fee Calculation**:
```
relayFee   = withdrawnAmount × relayFeeBPS / 10000
solverFee  = withdrawnAmount × solverFeeBPS / 10000
escrowAmount = withdrawnAmount - relayFee
netAmount    = withdrawnAmount - relayFee - solverFee
```

### Deposit Fees

```solidity
solverFee = totalPaid × solverFeeBPS / 10000
netDepositAmount = totalPaid - solverFee
```

---

## Security Considerations

### 1. ZK Proof Validation

All withdrawal operations validate Groth16 proofs:
- Context binding prevents proof reuse
- State root must be in recent history (ROOT_HISTORY_SIZE)
- ASP root must be latest
- Nullifier must not be spent
- Tree depths within bounds

### 2. Refund Mechanism

Cross-chain withdrawals include a refundCommitmentHash (9th signal):
- If intent expires without being filled
- Escrowed funds return to pool as new commitment
- User can withdraw refund as normal privacy pool withdrawal

### 3. Oracle Security

**Two oracle types prevent different attacks**:

| Oracle | Direction | Purpose | Required For |
|--------|-----------|---------|--------------|
| `fillOracle` | Dest → Origin | Proves fill happened | All intents |
| `intentOracle` | Origin → Dest | Proves intent is legitimate | Deposits only |

Deposits REQUIRE intentOracle validation to prevent depositor address spoofing.
Withdrawals skip it because ZK proof already validated user.

### 4. Settler Security

- Entrypoint is immutable (set once, cannot change)
- State machine prevents reentrancy
- Single solver requirement (no multi-solver fills)
- CEI pattern in all settlements

### 5. Paymaster Security

- Expected smart account must be configured
- No initCode (prevents deployment cost attacks)
- Embedded proof validation (doesn't trust external calls)
- Economics validation ensures fees cover gas

---

## Environment Variables

```bash
# Required
PRIVATE_KEY=           # Deployer private key (0x prefixed)
ETHERSCAN_API_KEY=     # For contract verification

# RPC URLs (configured in foundry.toml)
# base-sepolia: https://sepolia.base.org
# arbitrum-sepolia: Alchemy endpoint
```

---

## Testing

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testWithdrawal

# Verbose output
forge test -vvv

# Gas report
forge test --gas-report
```

---

## Common Patterns

### 1. Checking Known Root

```solidity
function _isKnownRoot(uint256 _root) internal view returns (bool) {
    if (_root == 0) return false;
    uint32 _index = currentRootIndex;
    for (uint32 _i = 0; _i < ROOT_HISTORY_SIZE; _i++) {
        if (_root == roots[_index]) return true;
        _index = (_index + ROOT_HISTORY_SIZE - 1) % ROOT_HISTORY_SIZE;
    }
    return false;
}
```

### 2. Context Validation

```solidity
uint256 expectedContext = uint256(
    keccak256(abi.encode(_withdrawal, SCOPE))
) % SNARK_SCALAR_FIELD;

if (proof.context() != expectedContext) revert ContextMismatch();
```

### 3. Transient Storage (EIP-1153)

```solidity
// Store in validation
assembly {
    tstore(0, withdrawnValue)
    tstore(1, relayFeeBPS)
    tstore(2, withdrawalRecipient)
}

// Read later
uint256 withdrawnValue;
assembly {
    withdrawnValue := tload(0)
}

// Clear after use
assembly {
    tstore(0, 0)
}
```

---

## Contract Addresses (Testnet)

> Note: These are testnet addresses. Refer to `packages/constants/src/contracts/constants.ts` in the app repo for current deployed addresses.

---

## Key Debugging Tips

1. **"InvalidOrderStatus"**: Check order state machine - likely already claimed/refunded
2. **"UnauthorizedCaller"**: Only entrypoint can call open() on InputSettler
3. **"IntentNotProven"**: Oracle hasn't attested to intent - check oracle configuration
4. **"FillOracleMismatch"**: Intent uses different fillOracle than configured
5. **"InvalidProcessooor"**: Withdrawal.processooor doesn't match expected address
6. **"ContextMismatch"**: ZK proof context doesn't match withdrawal data + scope
7. **"UnknownStateRoot"**: State root not in recent ROOT_HISTORY_SIZE roots
8. **"DeadlinePassed"**: Fill attempted after fillDeadline
9. **"ExpiryNotReached"**: Refund attempted before expires timestamp

---

## References

- [Privacy Pools Paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4563364)
- [Open Intent Framework](https://github.com/open-intent-framework/oif)
- [ERC-4337 Account Abstraction](https://eips.ethereum.org/EIPS/eip-4337)
- [Groth16 SNARKs](https://eprint.iacr.org/2016/260.pdf)

---

*Built for Ethereum privacy across chains*
