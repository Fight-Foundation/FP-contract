# FP1155 and Booster — Quick Reference

Use these addresses in apps and scripts. Always interact with the FP1155 proxy (not the implementation).

## Production (BSC Mainnet – chainId 56)
- FP1155 (UUPS proxy): `0xD0B591751E6aa314192810471461bDE963796306`
- FP1155 implementation (current, for verification only): `0xFC2a83E854C1D975284e4A13c0837A1b26e09221`
- Booster: `0x5E845Db62fDF02451cfC98be1e9927eB48a42fce`
- Base metadata URI: `https://assets.fight.foundation/fp/{id}.json`

## Testnet (BSC Testnet – chainId 97)
- FP1155 (UUPS proxy): `0x5E845Db62fDF02451cfC98be1e9927eB48a42fce`
- FP1155 implementation (logic): `0xFf2c7902FF6388553D1125Ca26545e30eaA1A4e6`
- Booster: `0x09107f150E478f7D81b35870e8c73c9Fb01Eda6B`
- Base metadata URI: `https://assets.fight.foundation/fp/{id}.json`

Notes:
- FP1155 is upgradeable via UUPS; storage/data lives in the proxy, so upgrades preserve balances and settings.
- ERC-1155 token URI resolves with {id} as 64-char lowercase hex (no 0x).

# FP1155 Deployment Summary
## Mainnet Proxy Address

**FP1155 Proxy (Mainnet):** `0xD0B591751E6aa314192810471461bDE963796306`
**Base Metadata URI:** `https://assets.fight.foundation/fp/{id}.json`
**Open Seasons:** 0, 321, 322 (all others locked)
**Admin/Season Admin:** 0xac5d932D7a16D74F713309be227659d387c69429
**CLAIM_SIGNER_ROLE:** 0x02D525601e60c2448Abb084e4020926A2Ae5cB01
**MINTER_ROLE:** 0xBf797273B60545882711f003094C065351a9CD7B
**Base URI Update (Mainnet):** set via `setURI("https://assets.fight.foundation/fp/{id}.json")`
  - Tx: `0x2639b6a9789819550e6f242dce30f45dd476508049ee71e3651a3fb8e220cfa1`
**Upgrade (Mainnet):** UUPS upgrade executed, proxy unchanged
  - Previous implementation: `0xD9fda390Fa212324F26276F14D6954076948C8d1`
  - New implementation: `0xFC2a83E854C1D975284e4A13c0837A1b26e09221`
  - Deploy impl tx: `0xf8de839546191818e91f37b9f760f5139434c0863d600b3dd4ca60a836cf461c`
  - Upgrade tx: `0x3f25bd8973f6c5adc8ec338f4f8a6eece6018de88414cdecc22911292613a8ac`
  - Verified: https://bscscan.com/address/0xFC2a83E854C1D975284e4A13c0837A1b26e09221#code
  - Note: State is preserved across upgrades (storage remains in proxy)
#### Allowlist updates (Mainnet FP1155 proxy)
- Removed from transfer allowlist → `0xf362fe668d93c43be16716a73702333795fbcea6`
  - Tx: `0x5b6cc71d7f2a62c141f48b0d11c5f850fb146eded1a06ebefaf06daaf653e372`
## ⚠️ Important: Upgradeable Contract

**FP1155 is now upgradeable using the UUPS (Universal Upgradeable Proxy Standard) pattern.**

When deploying or interacting with FP1155:
- Deploy via `DeployUpgradeable.s.sol` script (creates proxy + implementation)
- Always use the **proxy address** for interactions
- Only DEFAULT_ADMIN_ROLE can authorize upgrades
- Storage layout must remain compatible across upgrades

## Latest Deployments

### Previous Non-Upgradeable Deployments (Legacy)

Both mainnet and testnet had non-upgradeable deployments:

### BSC Mainnet (Chain 56)
- **Contract Address:** `0x5Fa58c84606Eba7000eCaF24C918086B094Db39a`
- **Deployer/Admin:** `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38`
- **Explorer:** https://bscscan.com/address/0x5fa58c84606eba7000ecaf24c918086b094db39a
- **Status:** ✅ Verified
- **Deployment Date:** November 5, 2025

#### Booster (Mainnet)
- **Booster Address:** `0x5E845Db62fDF02451cfC98be1e9927eB48a42fce`
- **Deployer/Admin:** `0xBf797273B60545882711f003094C065351a9CD7B`
- **FP1155 (proxy):** `0xD0B591751E6aa314192810471461bDE963796306`
- **Transactions:**
  - Deploy Booster (CREATE): `0x3f03aae3ec84f9bfaab0ae374f4741bcefa26d33b87639d5489840ea259bb481`
  - FP1155 grant TRANSFER_AGENT_ROLE → Booster: `0xf8fa5df63584ce0220797fa1d9e124776d76af885108732005d1ee57fa6e9b27`
  - FP1155 allowlist Booster: `0xbc027d5f78aad7d21b15106a9e56d9ed9a71aa48ca8ed0cc07efb186c20cf84d`
  - FP1155 allowlist Admin: `0xe415bb8b1199d6a793c401e2442b48b5c220e8546bd6c323ba49cc359cb521f5`
  - Booster grant OPERATOR_ROLE → Admin: `0x1d0852200ebd46875312941b1d3289b1d38a3503027d2269fd93a0ef90581afc`
  - Booster grant OPERATOR_ROLE → 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8: `0x752bd9feca2face897389d48c9521720c9ee53a48c82ba20dde392693ef603e0`
  - FP1155 allowlist 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8: `0x2a7a457a8effb8527861482feb5ef887fcf7883c351b93ea5d55dfc700cb67b1`
- **Verification:**
  - Verified: https://bscscan.com/address/0x5E845Db62fDF02451cfC98be1e9927eB48a42fce#code

### BSC Testnet (Chain 97)

- Previous testnet deploy (legacy, superseded): `0x5Fa58c84606Eba7000eCaF24C918086B094Db39a` (admin mistakenly set to `0x1804...`).

#### Redeploy (UUPS Proxy) — Active
- Date: November 13, 2025
- Base URI: `https://assets.fight.foundation/fp/{id}.json`
- Admin: `0xBf797273B60545882711f003094C065351a9CD7B`
- Implementation (logic): `0xFf2c7902FF6388553D1125Ca26545e30eaA1A4e6`
  - Tx: `0x9b8b4880ddce58d74774b30852d4889aa7af0407185a8345b31f3e0c4d317df7`
  - Verified: https://testnet.bscscan.com/address/0xff2c7902ff6388553d1125ca26545e30eaa1a4e6#code
- Proxy (use this for all interactions): `0x5E845Db62fDF02451cfC98be1e9927eB48a42fce`
  - Tx: `0xfe5db62aabff22d500a0c4b4a676bb46c2f190b869ce5e4b3b867dfba602c009`
  - Verified (ERC1967Proxy): https://testnet.bscscan.com/address/0x5e845db62fdf02451cfc98be1e9927eb48a42fce#code

Notes:
- The prior non-proxy testnet address is deprecated and not upgradeable.
- Always point apps and scripts to the proxy address above.

#### Booster (Testnet) — Using new FP1155 proxy
- Booster Address: `0x09107f150E478f7D81b35870e8c73c9Fb01Eda6B`
- Deployer/Admin: `0xBf797273B60545882711f003094C065351a9CD7B`
- FP1155 (proxy): `0x5E845Db62fDF02451cfC98be1e9927eB48a42fce`
- Transactions:
  - Deploy Booster (CREATE): `0x126787596abaa8c592b1256e0cefb1b5661638ebcb73bffd215680b4d55adc89`
  - FP1155 grant TRANSFER_AGENT_ROLE → Booster: `0xc48bd3e6680d143bb3b3bfe3d4f63b177094de9bc252eddfbc242cf9dca47bd5`
  - FP1155 allowlist Booster: `0xebf7c5dc8122f4dc11dd2cd68c988bbfb2d326c8c6d07f3c8bee4b519f3da8e3`
  - FP1155 allowlist Operator: `0xec68af926a1c8001f5a30cedc4a7d53b0e149a336474721a6eae2dafe13a4c62`
  - Booster grant OPERATOR_ROLE → 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8: `0xfdc551d71255214373c95041b760845d933886c3287124ec4856dde708f2a257`
- Verification:
  - Verified: https://testnet.bscscan.com/address/0x09107f150e478f7d81b35870e8c73c9fb01eda6b#code

#### Role grants (Testnet FP1155 proxy)
- CLAIM_SIGNER_ROLE → 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
  - Tx: `0x4be4756d6c68f853f8dc4124b4015dc83676e67230a10ca422cad33414ea4348`

#### Allowlist updates (Testnet FP1155 proxy)
- Added to transfer allowlist → `0x91341dbc9f531fedcf790b7cae85f997a8e1e9d4`
  - Tx: `0x2342b914e8ba3a19c8cf472fff48656b0899c188d7d399fe4c4014153c6bfe96`

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

## Role Grants (Testnet)

Active testnet at `0xD0B5…6306`:

- `MINTER_ROLE` (0x9f2d…56a6) → `0x3fDDF486b3f539F24aBD845674F18AE33Af668f8`
  - Tx: `0xa8735f669a7e477616d59e655048de8969c5699332cf06a2d96c31b050c51d9f`
- `TRANSFER_AGENT_ROLE` (0x9060…ed3b) → `0x96c7ecDa74057c62D16BfeD1822e6EF6ed12EC66`
  - Tx: `0x60d9edea2cebf0e77e681ce80640d6e22820ead7ff7b6f5f981c8ef5e3685c61`

Pending:
- `CLAIM_SIGNER_ROLE` assignment

## New Upgradeable Deployment Guide

### Deploy FP1155 with UUPS Proxy

**Step 1: Prepare Environment**
```bash
export PRIVATE_KEY=0x...
export ADMIN=0x...  # Optional, defaults to deployer
export BASE_URI="ipfs://base/{id}.json"  # Optional
export BSC_RPC_URL="https://bsc-dataseed.binance.org"
export BSCSCAN_API_KEY=...
```

**Step 2: Deploy to Testnet (BSC Testnet)**
```bash
forge script script/DeployUpgradeable.s.sol:DeployUpgradeable \
  --rpc-url "$BSC_TESTNET_RPC_URL" \
  --broadcast \
  --verify \
  -vvvv
```

**Step 3: Deploy to Mainnet (BSC)**
```bash
forge script script/DeployUpgradeable.s.sol:DeployUpgradeable \
  --rpc-url "$BSC_RPC_URL" \
  --broadcast \
  --verify \
  -vvvv
```

**Output:**
```
Deploying FP1155 (UUPS Upgradeable) with:
  deployer: 0x...
  admin: 0x...
  baseURI: ipfs://base/{id}.json
Implementation deployed at: 0x... (logic contract)
Proxy deployed at: 0x... (use this address!)

Use proxy address for interactions: 0x...
```

**Important:** Always use the **proxy address** for all interactions, not the implementation address.

### Upgrade to New Implementation

After initial deployment, you can upgrade the contract logic:

**Step 1: Set Proxy Address**
```bash
export PROXY_ADDRESS=0x...  # Your deployed proxy address
export PRIVATE_KEY=0x...    # Admin key (must have DEFAULT_ADMIN_ROLE)
```

**Step 2: Run Upgrade Script**
```bash
forge script script/UpgradeFP1155.s.sol:UpgradeFP1155 \
  --rpc-url "$BSC_RPC_URL" \
  --broadcast \
  --verify \
  -vvvv
```

**Output:**
```
Upgrading FP1155 proxy:
  proxy: 0x...
  admin: 0x...
New implementation deployed at: 0x...
Proxy upgraded successfully
```

**What happens during upgrade:**
- A new implementation contract is deployed
- The proxy's implementation pointer is updated
- All state remains in the proxy (no data migration needed)
- Users continue using the same proxy address

### Upgrade Safety Checklist

Before upgrading in production:
- [ ] Test the upgrade on testnet first
- [ ] Verify storage layout compatibility (no reordering/removing variables)
- [ ] Run full test suite with new implementation
- [ ] Use a multisig for admin role in production
- [ ] Have a rollback plan (keep previous implementation address)
- [ ] Consider adding a timelock before upgrades
- [ ] Document all changes in the upgrade

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
FP1155_ADDRESS=0x5E845Db62fDF02451cfC98be1e9927eB48a42fce
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

---

## Booster Contract Deployment

The **Booster** contract (`src/Booster.sol`) implements UFC Strike Now pick'em functionality where users boost fight predictions with FP tokens.

### Prerequisites

Before deploying Booster:
1. ✅ FP1155 contract must be deployed
2. ✅ Know the FP1155 contract address
3. ✅ Have operator address(es) ready
4. ✅ Optional: list of initial users to allowlist

### Deployment (Booster)

Deploy Booster with a simple cast transaction (example assumes constructor `(address fp1155, address admin)` – adjust if different):

```bash
export FP1155_ADDRESS=0xD0B591751E6aa314192810471461bDE963796306
export ADMIN_ADDRESS=$DEPLOYER

cast send $DEPLOYER_ADDRESS \
  "deployBooster(address,address)" \
  $FP1155_ADDRESS $ADMIN_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC_URL --private-key $PRIVATE_KEY # <— replace with actual deployment method
```

Then wire roles / allowlist:
```bash
# Grant OPERATOR_ROLE
cast send $BOOSTER_ADDRESS \
  "grantRole(bytes32,address)" $(cast keccak OPERATOR_ROLE) $OPERATOR_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC_URL --private-key $PRIVATE_KEY

# FP1155: grant TRANSFER_AGENT_ROLE to Booster
cast send $FP1155_ADDRESS \
  "grantRole(bytes32,address)" $(cast keccak TRANSFER_AGENT_ROLE) $BOOSTER_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC_URL --private-key $PRIVATE_KEY

# Allowlist Booster + operator
cast send $FP1155_ADDRESS "setTransferAllowlist(address,bool)" $BOOSTER_ADDRESS true --rpc-url $BSC_TESTNET_RPC_URL --private-key $PRIVATE_KEY
cast send $FP1155_ADDRESS "setTransferAllowlist(address,bool)" $OPERATOR_ADDRESS true --rpc-url $BSC_TESTNET_RPC_URL --private-key $PRIVATE_KEY
```

### Post-Deployment Configuration

**Verify Booster Deployment:**
```bash
# Check FP1155 address
cast call $BOOSTER_ADDRESS "FP()(address)" --rpc-url $RPC_URL

# Check operator role
cast call $BOOSTER_ADDRESS \
  "hasRole(bytes32,address)(bool)" \
  $(cast keccak OPERATOR_ROLE) \
  $OPERATOR_ADDRESS \
  --rpc-url $RPC_URL
```

**Grant Additional Operators:**
```bash
cast send $BOOSTER_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak OPERATOR_ROLE) \
  $NEW_OPERATOR \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_PK
```

**Allowlist More Users:**
```bash
cast send $FP1155_ADDRESS \
  "setTransferAllowlist(address,bool)" \
  $USER_ADDRESS \
  true \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_PK
```

### Event Lifecycle Management

Provision events manually or with your own script. (Previous one-shot script references removed pending update.)

**Purge After Deadline:**
```bash
cast send $BOOSTER_ADDRESS \
  "purgeEvent(string,address)" \
  "UFC_301" \
  $TREASURY_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $OPERATOR_PK
```

### Monitoring

**Key Events to Monitor:**
- `EventCreated(eventId, fightIds, seasonId)`
- `BoostPlaced(eventId, fightId, user, boostIndex, amount, winner, method)`
- `FightResultSubmitted(eventId, fightId, winner, method, ...)`
- `RewardClaimed(eventId, fightId, user, boostIndex, payout, points)`
- `EventPurged(eventId, recipient, amount)`

**Query Fight State:**
```bash
cast call $BOOSTER_ADDRESS \
  "getFight(string,uint256)" \
  "UFC_301" 1 \
  --rpc-url $RPC_URL
```

**Quote User Claimable (per fight):**
```bash
cast call $BOOSTER_ADDRESS \
  "quoteClaimable(string,uint256,address,bool)(uint256,uint256,uint256)" \
  "UFC_301" 1 $USER_ADDRESS true \
  --rpc-url $RPC_URL
```
Aggregate over all fights if you need a total prior to `claimReward(eventId)`.

### Security Checklist

- [ ] Booster has `TRANSFER_AGENT_ROLE` on FP1155
- [ ] Booster is allowlisted in FP1155
- [ ] Operator is allowlisted in FP1155
- [ ] All participating users are allowlisted in FP1155
- [ ] Operator keys are secured (consider multisig)
- [ ] Offchain points calculation is audited and tested
- [ ] Claim deadlines are set and communicated to users
- [ ] Monitoring/alerting is set up for critical events
- [ ] Emergency pause procedure is documented

### Testnet Addresses (Example)

```bash
FP1155_ADDRESS=0xD0B591751E6aa314192810471461bDE963796306
BOOSTER_ADDRESS=0x3153767cCBc04B7f3E65a422494eE40f6D70F525
OPERATOR_ADDRESS=0xBf797273B60545882711f003094C065351a9CD7B  # current admin as operator on testnet
```

### Testnet deployment (Nov 12, 2025)

- Network: BSC Testnet (97)
- Booster address: `0x3153767cCBc04B7f3E65a422494eE40f6D70F525`
- Admin: `0xBf797273B60545882711f003094C065351a9CD7B`
- FP1155 (proxy): `0xD0B591751E6aa314192810471461bDE963796306`

Transactions:
- Deploy Booster (CREATE)
  - Tx: `0xe722ef8f590031f66219e5c9e07fcb497722c42993a67c78b09248e868465edd`
- Grant TRANSFER_AGENT_ROLE to Booster on FP1155
  - Tx: `0x6604cc1080515f6ec6a5cf4c91ee516f90d9df5e8fb4feaa65e0152349a83bd7`
- Allowlist Booster in FP1155
  - Tx: `0x2574ae1919a30eaa385d149972d77de63f270dd01e20cfee206b106f8f69f3a0`
- Allowlist Admin in FP1155
  - Tx: `0x6866dc8bba2983aff06c88b912e65befab6ec6b46def1ef56e7f33993c15c494`
- Grant OPERATOR_ROLE to Admin on Booster
  - Tx: `0x3e9503f215ba30fed1a71b1866eb0a9ad2d3643517bbea1305accfce5bc69d65`
 - Booster grant OPERATOR_ROLE → 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
   - Tx: `0x0f5a7696875895b3e9d2cd44815c64b76e3301b2dc293c33274ebc60ce2861b0`
 - FP1155 allowlist 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
   - Tx: `0x683523216c4d15b720af9a48990a5a248cbe368696bb9ad1a2c63cf91133c22c`

Verification:
- Booster verified on BscScan Testnet: https://testnet.bscscan.com/address/0x3153767cCBc04B7f3E65a422494eE40f6D70F525#code

Pending follow-ups:
- Grant OPERATOR_ROLE on Booster to the production operator address (awaiting confirmation of the exact address format)
- Optionally remove operator allowlist for admin if not required

---

## Support

For contract interaction examples, see:
- [README.md](./README.md) - Full documentation
- [tools/sign-claim.ts](./tools/sign-claim.ts) - Claim signing utility
- [tools/submit-claim.ts](./tools/submit-claim.ts) - Claim submission utility
- [tools/validate-env.ts](./tools/validate-env.ts) - Environment validation

Contract ABI is available in `out/FP1155.sol/FP1155.json` after compilation.
