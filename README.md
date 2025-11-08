## FP (Fighting Points) — ERC-1155 on BSC

Seasonal, non-tradable reputation points. Each season is a tokenId. Transfers are restricted to an allowlist. At end of season, it's LOCKED (no mint/transfer; burns allowed). Built with OpenZeppelin and Foundry (TDD).

### Key features
- ERC-1155 with pause, burn, and access control
- Roles: DEFAULT_ADMIN, MINTER, TRANSFER_AGENT, SEASON_ADMIN, PAUSER
- Transfer allowlist for endpoints (sender and receiver must be allowlisted or have TRANSFER_AGENT role)
- Season status: OPEN or LOCKED (irreversible)
- Mint either by MINTER role or via user-submitted EIP-712 claim (signed by CLAIM_SIGNER); burn allowed by holders (even when LOCKED)

**Contracts:**
- `src/FP1155.sol` — Core FP token
- `src/Booster.sol` — UFC Strike Now pick'em boosting
- `src/Deposit.sol` — Sample agent deposit/withdraw

**Tests:**
- `test/FP1155.t.sol`
- `test/Booster.t.sol`
- `test/Deposit.t.sol`

**Deploy scripts:**
- `script/Deploy.s.sol` — Deploy FP1155
- `script/GrantRoles.s.sol` / `script/RevokeRoles.s.sol` — Role management
	- (Booster deployment currently done via manual cast/script; update when dedicated script is added)

**Server utilities:**
- `tools/sign-claim.ts`
- `tools/submit-claim.ts`

## How it works

### Token model
- Standard: ERC-1155
- Token IDs: `seasonId` (e.g., 2501 for Season 25.01)
- Supply: mintable; burnable by holders

### Transfer rules (enforced in `_update`)
- Mint (from == 0): season must be OPEN
- Burn (to == 0): always allowed, even when LOCKED
- Transfer (from != 0 and to != 0): season must be OPEN AND both endpoints must be either allowlisted or have TRANSFER_AGENT role

### Agent transfers (no user approval)
Some programs (like custody, escrow or wagering) need to move user FP without users setting `setApprovalForAll`. The contract exposes an agent-only method:

- `agentTransferFrom(address from, address to, uint256 seasonId, uint256 amount, bytes data)` — callable only by addresses with `TRANSFER_AGENT_ROLE`.

Behavior and guards:
- Still enforces all standard rules in `_update` (season must be OPEN for transfers; pause blocks ops)
- Endpoint checks: both `from` and `to` must pass the endpoint rule. An address passes this rule if it’s on the allowlist OR it has `TRANSFER_AGENT_ROLE`.
- Practically, the agent itself doesn’t need to be on the allowlist if it holds `TRANSFER_AGENT_ROLE`; end-users must be allowlisted for transfers involving them unless they also hold the agent role.

Sample integration: `src/Deposit.sol` uses `agentTransferFrom` to pull tokens from a user into the contract, and to send them back during withdraws. The contract must be granted `TRANSFER_AGENT_ROLE` to operate.

### Season lifecycle
- OPEN: normal behavior (allowlist enforced on transfers)
- LOCKED: no minting; no transfers; burns remain allowed
- Lock is irreversible by design

### Pause behavior
- `pause()`/`unpause()` via PAUSER_ROLE
- When paused, all mint/transfer/burn operations are blocked (including claims)

### Networks
- BSC Mainnet chainId: 56
- BSC Testnet chainId: 97
Set `--rpc-url` accordingly and ensure the EIP-712 domain uses the correct chainId.

## Roles and permissions
- DEFAULT_ADMIN_ROLE
	- Can set base URI, manage allowlist, grant/revoke roles
- MINTER_ROLE
	- Can call `mint`/`mintBatch` (subject to season OPEN)
- TRANSFER_AGENT_ROLE
	- Satisfies endpoint check for transfers without being on allowlist
- SEASON_ADMIN_ROLE
	- Can change season status OPEN → LOCKED (irreversible)
- PAUSER_ROLE
	- Can `pause()` and `unpause()`
- CLAIM_SIGNER_ROLE
	- Used by backend signers for the EIP-712 claim flow (see below)

## Signed-claim flow (user pays gas)
Let users bring their off-chain FP on-chain by submitting a server-signed claim. Users pay gas; you don’t sponsor.

### On-chain function
`claim(uint256 seasonId, uint256 amount, uint256 deadline, bytes signature)`
- Mints to `msg.sender` only
- Requires `block.timestamp <= deadline`
- Verifies EIP-712 signature from an address with `CLAIM_SIGNER_ROLE`
- Uses per-user `nonces[msg.sender]` to prevent replay and increments on success
- Still respects season OPEN check (mint blocked if season is LOCKED) and pause

### EIP-712 details
- Domain: `{ name: "FP1155", version: "1", chainId, verifyingContract }`
- Types:
	- `Claim(address account,uint256 seasonId,uint256 amount,uint256 nonce,uint256 deadline)`
- Message fields:
	- `account` — the user address (must equal `msg.sender` in claim)
	- `seasonId`, `amount` — what to mint
	- `nonce` — must equal `nonces[account]` on-chain at signing time
	- `deadline` — timestamp cutoff

### Server procedure
1) Read user nonce: `nonces[user]`
2) Build typed data `{account, seasonId, amount, nonce, deadline}`
3) Sign with server key that has `CLAIM_SIGNER_ROLE`
4) Return signature to the user

Example (TypeScript, ethers v6-style):
```ts
const domain = { name: "FP1155", version: "1", chainId, verifyingContract: fp1155Address };
const types = {
	Claim: [
		{ name: "account", type: "address" },
		{ name: "seasonId", type: "uint256" },
		{ name: "amount", type: "uint256" },
		{ name: "nonce", type: "uint256" },
		{ name: "deadline", type: "uint256" },
	],
};
const nonce = await fp.nonces(user);
const message = { account: user, seasonId, amount, nonce, deadline };
const signature = await serverSigner.signTypedData(domain, types, message);
```

CLI (Node):
```bash
# .env must include CLAIM_SIGNER_PK and RPC_URL (or BSC_TESTNET_RPC_URL/BSC_RPC_URL)
npm run sign:claim -- \
	--contract $FP1155_ADDRESS \
	--user $USER_ADDRESS \
	--season 2501 \
	--amount 100 \
	--deadline $(( $(date +%s) + 3600 ))
# Outputs JSON with signature you can pass to the client
```

### User procedure
1) Obtain signature blob from server
2) Submit on-chain:
```bash
cast send $FP1155_ADDRESS "claim(uint256,uint256,uint256,bytes)" \
	$SEASON_ID $AMOUNT $DEADLINE $SIGNATURE_HEX \
	--rpc-url "$BSC_TESTNET_RPC_URL" --private-key "$USER_PK"
```

CLI (Node):
```bash
# .env must include USER_PK and RPC_URL (or BSC_TESTNET_RPC_URL/BSC_RPC_URL)
npm run submit:claim -- \
	--contract $FP1155_ADDRESS \
	--season 2501 \
	--amount 100 \
	--deadline 1730851200 \
	--sig $SIGNATURE_HEX
```

Pitfalls:
- Ensure the signature is a 65-byte `0x`-hex string (r||s||v). If you use ethers v6 `signTypedData`, you’ll get the correct format.
- If the claim reverts with `claim: invalid signer`, check that the signer address has `CLAIM_SIGNER_ROLE`, the nonce matches on-chain, and the chainId/domain fields are correct.

## Operational runbook (admin)
- Grant roles
```bash
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak MINTER_ROLE) $MINTER --rpc-url "$RPC" --private-key "$ADMIN_PK"
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak TRANSFER_AGENT_ROLE) $AGENT --rpc-url "$RPC" --private-key "$ADMIN_PK"
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak CLAIM_SIGNER_ROLE) $SERVER_SIGNER --rpc-url "$RPC" --private-key "$ADMIN_PK"
```
- Manage allowlist
```bash
cast send $FP1155 "setTransferAllowlist(address,bool)" $ACCOUNT true --rpc-url "$RPC" --private-key "$ADMIN_PK"
```
- Lock season (irreversible)
```bash
cast send $FP1155 "setSeasonStatus(uint256,uint8)" $SEASON_ID 1 --rpc-url "$RPC" --private-key "$ADMIN_PK"
```
- Pause/unpause
```bash
cast send $FP1155 "pause()"   --rpc-url "$RPC" --private-key "$PAUSER_PK"
cast send $FP1155 "unpause()" --rpc-url "$RPC" --private-key "$PAUSER_PK"
```

### Agent setup (example with Deposit)
```bash
# grant TRANSFER_AGENT_ROLE to the Deposit contract
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak TRANSFER_AGENT_ROLE) $DEPOSIT --rpc-url "$RPC" --private-key "$ADMIN_PK"

# allowlist users that will interact (required for endpoint checks)
cast send $FP1155 "setTransferAllowlist(address,bool)" $USER true --rpc-url "$RPC" --private-key "$ADMIN_PK"
```

### Role revocation and rotation runbook
Use these steps to rotate or revoke sensitive roles (CLAIM_SIGNER, TRANSFER_AGENT, MINTER, PAUSER, SEASON_ADMIN). Ensure you have `DEFAULT_ADMIN_ROLE` to administer roles.

1) Verify current assignments
```bash
cast call $FP1155 "hasRole(bytes32,address)(bool)" $(cast keccak CLAIM_SIGNER_ROLE) $OLD_SIGNER --rpc-url "$RPC"
cast call $FP1155 "hasRole(bytes32,address)(bool)" $(cast keccak TRANSFER_AGENT_ROLE) $AGENT --rpc-url "$RPC"
```

2) Grant the new principal (if rotating)
```bash
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak CLAIM_SIGNER_ROLE) $NEW_SIGNER --rpc-url "$RPC" --private-key "$ADMIN_PK"
cast send $FP1155 "grantRole(bytes32,address)" $(cast keccak TRANSFER_AGENT_ROLE) $NEW_AGENT --rpc-url "$RPC" --private-key "$ADMIN_PK"
```

3) Revoke the old principal
```bash
cast send $FP1155 "revokeRole(bytes32,address)" $(cast keccak CLAIM_SIGNER_ROLE) $OLD_SIGNER --rpc-url "$RPC" --private-key "$ADMIN_PK"
cast send $FP1155 "revokeRole(bytes32,address)" $(cast keccak TRANSFER_AGENT_ROLE) $AGENT --rpc-url "$RPC" --private-key "$ADMIN_PK"
```

4) Optional: Encourage principals to self-`renounceRole` from their own address
```bash
cast send $FP1155 "renounceRole(bytes32,address)" $(cast keccak CLAIM_SIGNER_ROLE) $ME --rpc-url "$RPC" --private-key "$ME_PK"
```

5) Post-change validation
```bash
cast call $FP1155 "hasRole(bytes32,address)(bool)" $(cast keccak CLAIM_SIGNER_ROLE) $NEW_SIGNER --rpc-url "$RPC"
cast call $FP1155 "hasRole(bytes32,address)(bool)" $(cast keccak TRANSFER_AGENT_ROLE) $NEW_AGENT --rpc-url "$RPC"
```

Emergency response tips:
- Pause the contract to halt mint/transfer/burn if an agent/signing key is compromised.
- Revoke the compromised role immediately; if necessary, lock affected seasons to freeze transfers.
- Remove suspicious addresses from the allowlist.

## Guards, errors, and edge cases
- Mint when LOCKED → `mint: season locked`
- Transfer when LOCKED → `transfer: season locked`
- Transfer when endpoints not allowed → `transfer: endpoints not allowed`
- Claim with wrong signer → `claim: invalid signer`
- Claim after deadline → `claim: expired`
- All state-changing ops while paused → Pausable revert
- Unlock attempt after LOCKED → `locked: irreversible`
- Only role-bearers can call gated functions; otherwise AccessControl reverts

## API summary
- Admin/config
	- `setURI(string)` — DEFAULT_ADMIN_ROLE
	- `setTransferAllowlist(address,bool)` — DEFAULT_ADMIN_ROLE
	- `setSeasonStatus(uint256,uint8)` — SEASON_ADMIN_ROLE (0=OPEN, 1=LOCKED)
	- `pause()/unpause()` — PAUSER_ROLE
	- `grantRole/revokeRole/hasRole` — AccessControl
- Mint/burn/transfer
	- `mint(address,uint256,uint256,bytes)` — MINTER_ROLE (season must be OPEN)
	- `mintBatch(address,uint256[],uint256[],bytes)` — MINTER_ROLE
	- `burn(address,uint256,uint256)` and `burnBatch(...)` — holder can burn (allowed even when LOCKED)
	- `safeTransferFrom/safeBatchTransferFrom` — require season OPEN and endpoints allowed
	- `agentTransferFrom(address,address,uint256,uint256,bytes)` — TRANSFER_AGENT_ROLE can move tokens without prior user approval; still subject to season/allowlist/pause guards
- Claims
	- `claim(uint256 seasonId,uint256 amount,uint256 deadline,bytes signature)` — user call; requires valid EIP-712 signature from `CLAIM_SIGNER_ROLE`; increments `nonces[user]`
	- `nonces(address)` — current nonce per user
	- `DOMAIN_SEPARATOR()` / `CLAIM_TYPEHASH` — helpers for client tooling

## Prerequisites
- Foundry installed (`forge`, `cast`, `anvil`). See https://book.getfoundry.sh/
- .env with:
	- `PRIVATE_KEY` — deployer private key (hex, no 0x or with 0x both supported by Foundry)
	- `BSC_RPC_URL` — BSC mainnet RPC (optional)
	- `BSC_TESTNET_RPC_URL` — BSC testnet RPC
	- `ADMIN` — optional admin address for constructor (defaults to deployer)
	- `BASE_URI` — optional base metadata URI (default `ipfs://base/{id}.json`)
	- `BSCSCAN_API_KEY` — optional, for contract verification

## Develop

Build:
```bash
forge build
```

Test (TDD):
```bash
forge test
```

Format:
```bash
forge fmt
```

## Deploy

Testnet (BSC testnet):
```bash
forge script script/Deploy.s.sol:Deploy \
	--rpc-url "$BSC_TESTNET_RPC_URL" \
	--broadcast --verify \
	-vvvv
```

Mainnet (BSC):
```bash
forge script script/Deploy.s.sol:Deploy \
	--rpc-url "$BSC_RPC_URL" \
	--broadcast --verify \
	-vvvv
```

Note:
- `ADMIN` env var overrides the admin address; otherwise the deployer becomes admin.
- Verification requires `BSCSCAN_API_KEY`.
 - foundry.toml already reads `BSCSCAN_API_KEY` under `[etherscan]`, so `--verify` works out of the box.

## Security considerations
- Do not share the CLAIM_SIGNER private key; rotate on suspicion.
- Keep seasons LOCKED once the season ends; the lock is irreversible by design.
- Consider granting roles via multisig and using timelocks for sensitive ops.
- The claim flow mints to `msg.sender`; don’t try to proxy claims to third parties unless you fully understand the implications.

## Spec enforcement
Enforced in `_update` hook (OZ v5.1):
- Mint (from == 0): season must be OPEN.
- Burn (to == 0): always allowed, even when LOCKED.
- Transfer: season must be OPEN and both endpoints must be allowlisted or have TRANSFER_AGENT role.
- Pausable: pause blocks mint/transfer/burn.

Events:
- `SeasonStatusUpdated(seasonId, status)`
- `AllowlistUpdated(account, allowed)`
- `ClaimProcessed(account, seasonId, amount, nonce)`

Additional notes:
- Zero amounts are not allowed for `mint`, `mintBatch`, or `claim` (revert `amount=0`).
- Batch operations are atomic; if any id in a batch violates a rule (e.g., locked season), the entire batch reverts.
- `isTransfersAllowed(from, to, seasonId)` is a view helper that mirrors the transfer policy and is useful for preflight checks in clients.

## Next steps
- Add ignition scripts or TypeScript wrappers if integrating with a frontend.
- Consider adding AccessControlDefaultAdminRules for time-delayed admin ops.

---

## Booster Contract

`src/Booster.sol` implements a UFC Strike Now pick'em booster where users stake FP on fight predictions, managers can deposit bonus pools, and winners split the combined pool proportionally.

### Key Features
- **Events and Fights**: Each event has multiple fights; users boost their predictions for individual fights
- **Dual Pools**: Each fight has an original pool (user stakes) + bonus pool (manager deposits)
- **Offchain Points Calculation**: Server submits `totalWinningPoints` after offchain calculation with guardrails
- **Proportional Rewards**: Winners receive `(userPoints / totalWinningPoints) * totalPool`
- **Event-wide Claiming**: Single call `claimReward(eventId)` claims across all resolved fights for the caller
- **No-Contest Refunds**: `cancelFight(eventId,fightId)` lets operator refund user principals on cancelled/no-contest fights
- **Boost Cutoff**: Per-fight `boostCutoff` timestamp blocks new boosts/additions after cutoff
- **Minimum Boost Amount**: Global `minBoostAmount` deters dust spam
- **Helper Views**: `totalPool(eventId,fightId)` returns original+bonus pool
- **Claim Deadlines**: Optional per-event deadline; after deadline, operator can purge unclaimed funds
- **Transfer Agent Integration**: Uses FP1155 `agentTransferFrom` for seamless FP transfers

### Architecture

**Roles:**
- `OPERATOR_ROLE` — Single privileged role for all admin/management operations (create events, deposit bonuses, submit results, set deadlines, purge)

**Types:**
- `FightStatus`: OPEN → CLOSED → RESOLVED (forward-only state machine)
- `Corner`: RED, BLUE, NONE
- `WinMethod`: KNOCKOUT, SUBMISSION, DECISION, NO_CONTEST

**Scoring:**
- Users predict winner + method
- Correct winner only → `pointsForWinner` points
- Correct winner + method → `pointsForWinnerMethod` points
- Wrong winner → 0 points

### User Flow

1. **Place Boosts** (`placeBoosts`):
   - User stakes FP on fight predictions before fight status is CLOSED
   - Can place multiple boosts in one transaction
   - User must be allowlisted in FP1155

2. **Add to Existing Boost** (`addToBoost`):
   - Increase stake on an existing boost before fight closes
   - Same prediction (winner + method) maintained

3. **Claim Rewards** (`claimReward(eventId)`):
	- After fights are RESOLVED and results submitted
	- Claims rewards across all resolved fights in the event for the caller
	- Skips unresolved fights and losing boosts automatically
	- Must claim before event deadline (if set)

### Operator Flow

1. **Create Event** (`createEvent`):
   - Define event ID, fight IDs, and season ID
   - Initialize all fights as OPEN

2. **Deposit Bonuses** (`depositBonus`):
   - Add FP to fight bonus pools before resolution
   - Optional; fights can have zero bonus

3. **Update Fight Status** (`updateFightStatus`):
   - Optional manual control to close betting windows
   - Forward-only: OPEN → CLOSED → RESOLVED

4. **Submit Results** (`submitFightResult`):
   - After fight ends, operator submits:
     - Actual winner and method
     - Points awarded for correct predictions
     - `totalWinningPoints` (sum of all winning users' points, calculated offchain)
   - Sets fight status to RESOLVED

5. **Set Claim Deadline** (`setEventClaimDeadline`):
   - Optional; set unix timestamp after which claims are rejected
   - Non-decreasing (can extend but not shorten)
   - 0 = no deadline

6. **Set Boost Cutoff** (`setFightBoostCutoff`):
	- Per-fight timestamp after which placing new boosts or increasing existing ones is blocked

7. **Set Minimum Boost** (`setMinBoostAmount`):
	- Enforce a minimum FP amount per boost to avoid spam

8. **Cancel Fight / Refund** (`cancelFight`):
	- Marks fight as cancelled (no-contest); users can claim their principal back

9. **Purge Unclaimed Funds** (`purgeEvent`):
   - After claim deadline passes
   - Sweep all unclaimed FP from resolved fights to recipient
   - Emits `FightPurged` and `EventPurged` events

### View Functions

- `getEvent(eventId)` → seasonId, fightIds, exists
- `getEventClaimDeadline(eventId)` → deadline timestamp
- `getFight(eventId, fightId)` → status, winner, method, pools, points, claimed amounts, boostCutoff, cancelled
- `getUserBoosts(eventId, fightId, user)` → array of user's boosts
- `getUserBoostIndices(eventId, fightId, user)` → indices helper (optional; no longer required for claiming)
- `calculateUserPoints(...)` → points earned for a prediction
- `quoteClaimable(eventId, fightId, user, enforceDeadline)` → total claimable, original share, bonus share
- `totalPool(eventId, fightId)` → original + bonus pool combined
- `minBoostAmount()` → global minimum boost setting

### Integration Requirements

**FP1155 Setup:**
1. Grant Booster contract `TRANSFER_AGENT_ROLE`
2. Allowlist Booster contract (`setTransferAllowlist(boosterAddress, true)`)
3. Allowlist operator address
4. Allowlist all participating users

**Booster Setup:**
1. Deploy Booster with FP1155 address and admin
2. Grant `OPERATOR_ROLE` to operator address(es)

### Events

- `EventCreated`, `EventClaimDeadlineUpdated`
- `FightStatusUpdated`, `BonusDeposited`
- `BoostPlaced`, `BoostIncreased`
- `FightResultSubmitted`, `RewardClaimed`
- `FightPurged`, `EventPurged`

### Example Usage

**Deploy and setup:**
```bash
# Deploy Booster (cast or custom script) then configure roles/allowlist:
export FP1155_ADDRESS=0x...
export BOOSTER_ADDRESS=0x...
export EVENT_ID=UFC_301
export SEASON_ID=1
export FIGHT_IDS=1,2,3
```

Create event and seed boosts using cast or your own provisioning script.

**User places boosts:**
```bash
cast send $BOOSTER_ADDRESS \
  "placeBoosts(string,(uint256,uint256,uint8,uint8)[])" \
  "UFC_301" \
  "[(1,100,0,0),(2,200,1,2)]" \
  --rpc-url $RPC_URL --private-key $USER_PK
```

**Operator submits results:**
```bash
cast send $BOOSTER_ADDRESS \
  "submitFightResult(string,uint256,uint8,uint8,uint256,uint256,uint256)" \
  "UFC_301" 1 0 0 10 25 350 \
  --rpc-url $RPC_URL --private-key $OPERATOR_PK
```

**User claims rewards (event-wide):**
```bash
cast send $BOOSTER_ADDRESS \
	"claimReward(string)" \
	"UFC_301" \
	--rpc-url $RPC_URL --private-key $USER_PK
```

**Quote claimable before claiming (per fight):**
```bash
cast call $BOOSTER_ADDRESS \
  "quoteClaimable(string,uint256,address,bool)(uint256,uint256,uint256)" \
  "UFC_301" 1 $USER_ADDRESS true \
  --rpc-url $RPC_URL
```

### Lifecycle

Typical sequence (manual or scripted):
1. `createEvent(eventId, fightIds, seasonId)`
2. (Optional) `setFightBoostCutoff(eventId, fightId, cutoff)` / `depositBonus(eventId, fightId, amount)`
3. Users: `placeBoosts(eventId, BoostInput[])`
4. Operator: `submitFightResult(eventId, fightId, winner, method, pointsWinner, pointsWinnerMethod, totalWinningPoints)`
5. Users: `claimReward(eventId)` before deadline
6. (Optional) Operator: `purgeEvent(eventId, recipient)` after deadline

**Purge after deadline:**
```bash
cast send $BOOSTER_ADDRESS \
  "purgeEvent(string,address)" \
  "UFC_301" $RECIPIENT_ADDRESS \
  --rpc-url $RPC_URL --private-key $OPERATOR_PK
```

### Security Considerations

- **OPERATOR_ROLE is powerful**: Can create events, submit results, and purge funds
  - Use multisig or timelock for production
  - Rotate keys regularly
- **Offchain calculation trust**: `totalWinningPoints` must be accurate
  - Incorrect values distort payouts
  - Consider on-chain verification or dispute mechanism for production
- **Deadline enforcement**: Claims rejected after deadline
  - Set reasonable deadlines (e.g., 7-30 days)
  - Communicate clearly to users
- **Boost cutoffs**: Respect `boostCutoff` per fight; no new boosts/additions after cutoff
- **Minimum boost**: Enforce `minBoostAmount` to prevent dust spam
- **Purge mechanism**: Operator can sweep unclaimed funds after deadline
  - Ensure deadline is well-communicated
  - Consider grace period before purge
- **FP1155 integration**: Both users and Booster must be allowlisted
  - Verify allowlist before operations
  - Monitor transfer agent role assignments

---
