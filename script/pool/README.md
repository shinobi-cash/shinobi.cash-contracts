# Pool Chain Deployment Scripts

Deploy Shinobi.cash pool infrastructure on any supported chain.

## Configuration Structure

```
script/config/
├── pools/
│   ├── pool.template.json      # Template for new pools
│   └── arbitrum-sepolia.json   # Arbitrum Sepolia config
└── ChainConfig.sol             # Config reader library

deployments/
└── arbitrum-sepolia.json       # Deployment output with addresses + block numbers
```

## Input Config

Create `config/pools/{pool-key}.json`:

```json
{
  "name": "Arbitrum Sepolia",
  "chainId": 421614,
  "hyperlaneDomainId": 421614,
  "hyperlaneMailbox": "0x598facE78a4302f11E3de0bee1894Da0b2Cb71F8",
  "erc4337Entrypoint": "0x0000000071727De22E5E9d8BAf0edAc6f37da032",
  "config": {
    "minimumDeposit": "1000000000000000",
    "vettingFeeBPS": 100,
    "maxRelayFeeBPS": 1500
  }
}
```

## Output Deployment

Scripts write to `deployments/{pool-key}.json`:

```json
{
  "chainName": "arbitrum-sepolia",
  "chainId": 421614,
  "deployer": "0x...",
  "deployedAt": 1704067200,
  "verifiers": {
    "withdrawal": { "address": "0x...", "blockNumber": 12345 }
  },
  "contracts": {
    "entrypoint": { "address": "0x...", "blockNumber": 12346 }
  },
  "paymasters": {
    "simple": { "address": "0x...", "blockNumber": 12347 }
  }
}
```

Block numbers are recorded for indexer start points.

## Deployment Steps

All scripts use `POOL_KEY` environment variable.

### Step 1: Deploy ZK Verifiers

```bash
POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_01_Verifiers.s.sol:DeployPool_01_Verifiers \
  --rpc-url $RPC_URL --broadcast --verify
```

### Step 2: Deploy Entrypoint

```bash
POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_02_Entrypoint.s.sol:DeployPool_02_Entrypoint \
  --rpc-url $RPC_URL --broadcast --verify
```

### Step 3: Deploy Privacy Pool

```bash
POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_03_PrivacyPool.s.sol:DeployPool_03_PrivacyPool \
  --rpc-url $RPC_URL --broadcast --verify
```

### Step 4: Deploy Settlers & Oracle

```bash
POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_04_Settlers.s.sol:DeployPool_04_Settlers \
  --rpc-url $RPC_URL --broadcast --verify
```

### Step 5: Setup Entrypoint

```bash
POOL_KEY=arbitrum-sepolia forge script script/pool/DeployPool_05_Setup.s.sol:DeployPool_05_Setup \
  --rpc-url $RPC_URL --broadcast
```

### Step 6: Deploy Paymasters (Optional)

```bash
POOL_KEY=arbitrum-sepolia EXPECTED_SMART_ACCOUNT=0x... forge script \
  script/pool/DeployPool_06_Paymasters.s.sol:DeployPool_06_Paymasters \
  --rpc-url $RPC_URL --broadcast --verify
```

## Deploying a New Pool Chain

1. Copy template: `cp config/pools/pool.template.json config/pools/my-chain.json`
2. Fill in chain-specific values (chainId, hyperlaneMailbox, etc.)
3. Run scripts 1-6 with `POOL_KEY=my-chain`
4. Deployment output saved to `deployments/my-chain.json`

## Next Steps

After pool deployment:
1. Add origin chains using `script/chains/` scripts
2. Use `deployments/{pool-key}.json` block numbers for indexer configuration
