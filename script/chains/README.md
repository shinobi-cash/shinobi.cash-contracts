# Adding New Chains to Shinobi.cash

This directory contains scripts for adding new origin/destination chains to the Shinobi.cash protocol.

## How It Works

1. **Input**: Chain metadata from `script/config/origins/{ORIGIN_KEY}.json`
2. **Output**: Deployed addresses and block numbers to `deployments/{chain-name}.json`
3. **Cross-reference**: Scripts read from both pool and origin deployment files

## Overview

When adding a new chain, users can:
- **Deposit** from the new chain → pool chain
- **Withdraw** from pool chain → the new chain

## Prerequisites

1. Pool chain must be deployed (run `script/pool/` scripts first)
2. `deployments/{pool-key}.json` must exist with all pool contracts

## Adding a New Chain to Config

1. Find the Hyperlane Mailbox address at [docs.hyperlane.xyz](https://docs.hyperlane.xyz)
2. Create `script/config/origins/{your-chain-key}.json`:

```json
{
  "name": "Your Chain Name",
  "chainId": 12345,
  "hyperlaneDomainId": 12345,
  "hyperlaneMailbox": "0x...",
  "poolKey": "arbitrum-sepolia",
  "config": {
    "fillDeadline": 82800,
    "expiry": 86400,
    "minimumDepositAmount": "10000000000000000",
    "defaultSolverFeeBPS": 500,
    "maxSolverFeeBPS": 1000
  }
}
```

## Deployment Steps

### Step 1: Deploy Contracts on New Chain

```bash
ORIGIN_KEY=your-chain-key forge script script/chains/AddChain_01_DeployOriginContracts.s.sol \
  --rpc-url <your-chain-rpc> \
  --broadcast --verify
```

Creates `deployments/{your-chain-name}.json` with:
- HyperlaneOracle
- ShinobiCrosschainDepositEntrypoint
- ShinobiInputSettler
- ShinobiWithdrawalOutputSettler

### Step 2: Configure Pool Chain

```bash
ORIGIN_KEY=your-chain-key forge script script/chains/AddChain_02_ConfigurePoolChain.s.sol \
  --rpc-url <pool-chain-rpc> \
  --broadcast
```

Reads from both deployment files and configures:
- DepositOutputSettler to accept deposits from new chain
- Entrypoint to send withdrawals to new chain

### Step 3: Configure Origin Chain

```bash
ORIGIN_KEY=your-chain-key forge script script/chains/AddChain_03_ConfigureOriginChain.s.sol \
  --rpc-url <your-chain-rpc> \
  --broadcast
```

Configures the DepositEntrypoint with:
- Input settler, fill oracle, intent oracle
- Destination configuration (pool chain)
- Deadlines, fees, asset mappings
- Hyperlane relay configuration

## Output File Format

Each origin chain gets `deployments/{chain-name}.json`:

```json
{
  "chainName": "base-sepolia",
  "chainId": 84532,
  "deployer": "0x...",
  "deployedAt": 1704067200,
  "contracts": {
    "hyperlaneOracle": { "address": "0x...", "blockNumber": 12345 },
    "depositEntrypoint": { "address": "0x...", "blockNumber": 12346 },
    "inputSettler": { "address": "0x...", "blockNumber": 12347 },
    "withdrawalOutputSettler": { "address": "0x...", "blockNumber": 12348 }
  }
}
```

## Script Summary

| Script | Chain | Description |
|--------|-------|-------------|
| `AddChain_01_DeployOriginContracts` | New Chain | Deploy all contracts on new origin |
| `AddChain_02_ConfigurePoolChain` | Pool | Configure pool to accept new chain |
| `AddChain_03_ConfigureOriginChain` | New Chain | Configure deposit entrypoint |

## Troubleshooting

### "Pool HyperlaneOracle not deployed"
Run the pool deployment scripts first (`script/pool/`). HyperlaneOracle is deployed in Step 4.

### "Origin HyperlaneOracle not deployed"
Run Step 1 on the origin chain first.

### "Must run on pool chain!"
Check your RPC URL - Step 2 must run on the pool chain.

### "Must run on origin chain!"
Check your RPC URL - Steps 1 and 3 must run on the new chain.
