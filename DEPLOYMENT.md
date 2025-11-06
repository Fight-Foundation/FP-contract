# FP1155 Deployment Summary

## Contract Deployments

Both mainnet and testnet deployments are **verified** and live at the same deterministic address.

### BSC Mainnet (Chain 56)
- **Contract Address:** `0x5Fa58c84606Eba7000eCaF24C918086B094Db39a`
- **Deployer/Admin:** `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38`
- **Explorer:** https://bscscan.com/address/0x5fa58c84606eba7000ecaf24c918086b094db39a
- **Status:** ✅ Verified
- **Deployment Date:** November 5, 2025

### BSC Testnet (Chain 97)
- **Contract Address:** `0x5Fa58c84606Eba7000eCaF24C918086B094Db39a`
- **Deployer/Admin:** `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38`
- **Transaction Hash:** `0xf4ac315a9945a0b0d3977f0df1010e0afc692ca792a8c48a6d397a6272c1f051`
- **Block:** 71393353
- **Explorer:** https://testnet.bscscan.com/address/0x5fa58c84606eba7000ecaf24c918086b094db39a
- **Status:** ✅ Verified
- **Gas Used:** 4,424,692 (0.0004424692 BNB)
- **Deployment Date:** November 5, 2025

## Constructor Parameters

Both deployments used identical constructor arguments:

```solidity
baseURI: "ipfs://base/{id}.json"
admin: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
```

## Initial Roles Granted

The following roles were granted to the admin address (`0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38`) during deployment:

- `DEFAULT_ADMIN_ROLE` (0x00...00)
- `PAUSER_ROLE` (0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a)
- `SEASON_ADMIN_ROLE` (0x5effce7625dfa93143b52c2e2a8c180a76b28971dedae188ed1b54a687d2c74b)

## Roles Still Requiring Assignment

The following roles need to be granted to appropriate addresses:

- `MINTER_ROLE` (0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6)
- `CLAIM_SIGNER_ROLE` (0x0ef29d234fa2d688cebdd72371a2fed0705633af97ae1707dc03d645587211cb)
- `TRANSFER_AGENT_ROLE` (0x90601cb45097851a246a5f8a72fbb27b3ef393b2a92d8fdd7aa24b1be6b2ed3b)

## Post-Deployment Setup

### 1. Grant Operational Roles

**For Mainnet:**
```bash
# Grant MINTER_ROLE to minting service
cast send 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a \
  "grantRole(bytes32,address)" \
  0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 \
  <MINTER_ADDRESS> \
  --rpc-url $BSC_RPC_URL \
  --private-key $PRIVATE_KEY

# Grant CLAIM_SIGNER_ROLE to claim signing service
cast send 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a \
  "grantRole(bytes32,address)" \
  0x0ef29d234fa2d688cebdd72371a2fed0705633af97ae1707dc03d645587211cb \
  <CLAIM_SIGNER_ADDRESS> \
  --rpc-url $BSC_RPC_URL \
  --private-key $PRIVATE_KEY

# Grant TRANSFER_AGENT_ROLE (if using transfer agents)
cast send 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a \
  "grantRole(bytes32,address)" \
  0x90601cb45097851a246a5f8a72fbb27b3ef393b2a92d8fdd7aa24b1be6b2ed3b \
  <TRANSFER_AGENT_ADDRESS> \
  --rpc-url $BSC_RPC_URL \
  --private-key $PRIVATE_KEY
```

**For Testnet:** Replace `$BSC_RPC_URL` with `$BSC_TESTNET_RPC_URL`

### 2. Configure Transfer Allowlist (if needed)

```bash
# Add addresses to transfer allowlist
cast send 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a \
  "setTransferAllowlist(address,bool)" \
  <USER_ADDRESS> \
  true \
  --rpc-url $BSC_RPC_URL \
  --private-key $PRIVATE_KEY
```

### 3. Update Environment

Update your `.env` file with the deployed contract address:
```bash
FP1155_ADDRESS=0x5Fa58c84606Eba7000eCaF24C918086B094Db39a
```

## Testing the Deployment

### Check Contract Status
```bash
# Verify contract is paused (default state is unpaused)
cast call 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a "paused()(bool)" --rpc-url $BSC_RPC_URL

# Check season status for season 0
cast call 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a "getSeasonStatus(uint256)(uint8)" 0 --rpc-url $BSC_RPC_URL

# Check if address has admin role
cast call 0x5Fa58c84606Eba7000eCaF24C918086B094Db39a \
  "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 \
  --rpc-url $BSC_RPC_URL
```

### Test Claim Flow (Testnet)

1. **Generate a claim signature:**
   ```bash
   npm run sign-claim
   ```

2. **Submit the claim:**
   ```bash
   npm run submit-claim
   ```

## Network Configuration

### RPC Endpoints
- **Mainnet:** `https://bsc-dataseed.binance.org`
- **Testnet:** `https://bsc-testnet.publicnode.com`

### Block Explorers
- **Mainnet:** https://bscscan.com
- **Testnet:** https://testnet.bscscan.com

## Security Considerations

⚠️ **Important:**
- The deployer private key (`PRIVATE_KEY` in `.env`) has full admin control
- Store this key securely and never commit it to version control
- Consider using a multisig wallet for the `DEFAULT_ADMIN_ROLE` in production
- The `CLAIM_SIGNER_ROLE` key should be stored securely on your backend server
- Regularly rotate keys and monitor role assignments

## Contract Features

Both deployments include:
- ✅ ERC-1155 multi-token standard
- ✅ Role-based access control (6 roles)
- ✅ Season-based mechanics (OPEN/LOCKED states)
- ✅ Transfer allowlist enforcement
- ✅ EIP-712 signed claim flow
- ✅ Pause/unpause functionality
- ✅ Burn functionality
- ✅ Batch operations support

## Next Steps

1. ✅ Deploy contracts - **COMPLETE**
2. ✅ Verify on BscScan - **COMPLETE**
3. ⏳ Grant operational roles (MINTER, CLAIM_SIGNER, TRANSFER_AGENT)
4. ⏳ Configure transfer allowlist (if using restricted transfers)
5. ⏳ Set up backend claim signing service
6. ⏳ Test claim flow end-to-end on testnet
7. ⏳ Monitor events and transactions
8. ⏳ Consider admin key migration to multisig (for production)

## Support

For contract interaction examples, see:
- [README.md](./README.md) - Full documentation
- [tools/sign-claim.ts](./tools/sign-claim.ts) - Claim signing utility
- [tools/submit-claim.ts](./tools/submit-claim.ts) - Claim submission utility
- [tools/validate-env.ts](./tools/validate-env.ts) - Environment validation

Contract ABI is available in `out/FP1155.sol/FP1155.json` after compilation.
