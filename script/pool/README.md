# Pool Chain Deployment Scripts

Deploy Shinobi.cash pool infrastructure on any supported chain.

## Configuration Structure

```
script/config/
├── pools/
│   ├── pool.template.json      # Template for new pools
│   └── arbitrum-sepolia.json   # Arbitrum Sepolia config
├── origins/
│   └── base-sepolia.json       # Origin chain config
└── ChainConfig.sol             # Config reader library

deployments/
└── arbitrum-sepolia.json       # Deployment output with addresses + block numbers
```

## Deployment Steps

All scripts use `POOL_KEY` environment variable. Run in order:

| Step | Script | Description |
|------|--------|-------------|
| 1 | `01_Deploy_Verifiers.s.sol` | 5 ZK verifiers |
| 2 | `02_Deploy_DepositFacet.s.sol` | DepositFacet |
| 3 | `03_Deploy_CrosschainDepositFacet.s.sol` | CrosschainDepositFacet |
| 4 | `04_Deploy_WithdrawFacet.s.sol` | WithdrawFacet |
| 5 | `05_Deploy_CrosschainWithdrawFacet.s.sol` | CrosschainWithdrawFacet |
| 6 | `06_Deploy_Withdraw2Facet.s.sol` | Withdraw2Facet |
| 7 | `07_Deploy_CrosschainWithdraw2Facet.s.sol` | CrosschainWithdraw2Facet |
| 8 | `08_Deploy_RagequitFacet.s.sol` | RagequitFacet |
| 9 | `09_Deploy_PoolDiamond.s.sol` | PoolDiamond proxy |
| 10 | `10_Deploy_Settlers.s.sol` | Oracle + settlers |
| 11 | `11_Setup_PoolDiamond.s.sol` | Diamond config |
| 12 | `12_Deploy_Paymasters.s.sol` | 4 ERC-4337 paymasters |
| 13 | `13_Setup_WithdrawalChains.s.sol` | Cross-chain config |

### Example

```bash
# Steps 1-12: Pool chain
POOL_KEY=arbitrum-sepolia forge script script/pool/01_Deploy_Verifiers.s.sol:Deploy_Verifiers \
  --rpc-url $RPC_URL --broadcast --verify

# ... repeat for steps 2-12 ...

# Step 13: Requires both pool and origin keys
POOL_KEY=arbitrum-sepolia ORIGIN_KEY=base-sepolia forge script \
  script/pool/13_Setup_WithdrawalChains.s.sol:Setup_WithdrawalChains \
  --rpc-url $RPC_URL --broadcast
```

## Deploying a New Pool

1. Copy template: `cp config/pools/pool.template.json config/pools/my-chain.json`
2. Fill in chain-specific values (chainId, hyperlaneMailbox, etc.)
3. Run scripts 1-13 with `POOL_KEY=my-chain`
4. Deployment output saved to `deployments/my-chain.json`

## Next Steps

After pool deployment:
1. Add origin chains using `script/chains/` scripts
2. Use `deployments/{pool-key}.json` block numbers for indexer configuration
