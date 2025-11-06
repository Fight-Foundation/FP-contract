## FP (Fighting Points) — ERC-1155 on BSC

Seasonal, non-tradable reputation points. Each season is a tokenId. Transfers are restricted to an allowlist. At end of season, it’s LOCKED (no mint/transfer; burns allowed). Built with OpenZeppelin and Foundry (TDD).

### Key features
- ERC-1155 with pause, burn, and access control
- Roles: DEFAULT_ADMIN, MINTER, TRANSFER_AGENT, SEASON_ADMIN, PAUSER
- Transfer allowlist for endpoints (sender and receiver must be allowlisted or have TRANSFER_AGENT role)
- Season status: OPEN or LOCKED (irreversible)
- Mint either by MINTER role or via user-submitted EIP-712 claim (signed by CLAIM_SIGNER); burn allowed by holders (even when LOCKED)

Contract: `src/FP1155.sol`
Tests: `test/FP1155.t.sol`
Deploy script: `script/Deploy.s.sol`
Server utility: `tools/sign-claim.ts`
Client utility: `tools/submit-claim.ts`

## How it works

### Token model
- Standard: ERC-1155
- Token IDs: `seasonId` (e.g., 2501 for Season 25.01)
- Supply: mintable; burnable by holders

### Transfer rules (enforced in `_update`)
- Mint (from == 0): season must be OPEN
- Burn (to == 0): always allowed, even when LOCKED
- Transfer (from != 0 and to != 0): season must be OPEN AND both endpoints must be either allowlisted or have TRANSFER_AGENT role

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

Signer rotation:
- Grant the new signer: `grantRole(CLAIM_SIGNER_ROLE, newSigner)`
- Revoke the old signer: `revokeRole(CLAIM_SIGNER_ROLE, oldSigner)`

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
