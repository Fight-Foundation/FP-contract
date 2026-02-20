# DailyLottery Contract

## Overview

DailyLottery is a daily lottery system built for the UFC Strike / FightFi ecosystem. Each day (UTC) constitutes one lottery round. Users participate by claiming **free entries** (authorized by a backend signer via EIP-712 signatures) or by **purchasing entries** with FP tokens (which get burned). An admin draws the winner off-chain and the contract distributes the prize.

**Contract:** `src/DailyLottery.sol`
**Network:** BSC (Testnet & Mainnet)
**Pattern:** UUPS Upgradeable Proxy (ERC1967Proxy)
**Solidity:** ^0.8.20
**Dependencies:** OpenZeppelin Contracts Upgradeable v5

---

## Table of Contents

- [Architecture](#architecture)
- [Roles & Access Control](#roles--access-control)
- [How It Works](#how-it-works)
  - [Round Lifecycle](#round-lifecycle)
  - [Free Entries (EIP-712)](#free-entries-eip-712)
  - [Paid Entries](#paid-entries)
  - [Winner Drawing](#winner-drawing)
- [Configuration](#configuration)
  - [Default Values](#default-values)
  - [Per-Round Configuration](#per-round-configuration)
- [Data Structures](#data-structures)
- [Events](#events)
- [View Functions](#view-functions)
- [Deployment](#deployment)
  - [Initial Deployment](#initial-deployment)
  - [Post-Deployment Setup](#post-deployment-setup)
  - [Upgrading](#upgrading)
- [Integration with FP1155](#integration-with-fp1155)
- [Backend Integration Guide](#backend-integration-guide)
  - [Generating Free Entry Signatures](#generating-free-entry-signatures)
  - [Drawing a Winner](#drawing-a-winner)
- [TypeScript Tools](#typescript-tools)
- [Security Considerations](#security-considerations)
- [Test Coverage](#test-coverage)
- [FAQ](#faq)

---

## Architecture

```
                    ┌─────────────────────┐
                    │    ERC1967Proxy      │  <-- Users interact with this address
                    │  (proxy address)     │
                    └─────────┬───────────┘
                              │ delegatecall
                    ┌─────────▼───────────┐
                    │   DailyLottery      │  <-- Implementation (upgradeable via UUPS)
                    │                     │
                    │  Initializable       │
                    │  UUPSUpgradeable     │
                    │  AccessControl       │
                    │  ReentrancyGuard     │
                    │  Pausable            │
                    │  EIP712             │
                    │  IERC1155Receiver    │
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────▼──────┐ ┌─────▼─────┐ ┌───────▼──────┐
     │    FP1155      │ │  IERC20   │ │  Backend     │
     │  (ERC1155)     │ │(USDT/USDC)│ │  Signer      │
     │ burn entries   │ │  prizes   │ │  (EIP-712)   │
     └───────────────┘ └───────────┘ └──────────────┘
```

**Inheritance chain:**
- `Initializable` - Proxy initialization pattern
- `UUPSUpgradeable` - Allows contract upgrades via `upgradeToAndCall()`
- `AccessControlUpgradeable` - Role-based permissions
- `ReentrancyGuardUpgradeable` - Protects against reentrancy attacks
- `PausableUpgradeable` - Emergency pause mechanism
- `EIP712Upgradeable` - Structured data signing (EIP-712 domain: `"DailyLottery"`, version `"1"`)
- `IERC1155Receiver` - Can receive FP tokens (ERC1155)

**Storage gap:** `uint256[50] private __gap` reserved for future upgrades.

---

## Roles & Access Control

| Role | Identifier | Capabilities |
|------|-----------|-------------|
| `DEFAULT_ADMIN_ROLE` | `0x00` (OZ default) | Upgrade contract (UUPS), grant/revoke roles |
| `LOTTERY_ADMIN_ROLE` | `keccak256("LOTTERY_ADMIN_ROLE")` | Pause/unpause, set defaults, update round params, draw winners |
| `FREE_ENTRY_SIGNER_ROLE` | `keccak256("FREE_ENTRY_SIGNER_ROLE")` | Sign EIP-712 free entry authorizations (backend wallet) |

**On initialization:**
- `_defaultAdmin` receives `DEFAULT_ADMIN_ROLE`
- `_lotteryAdmin` receives both `LOTTERY_ADMIN_ROLE` and `FREE_ENTRY_SIGNER_ROLE`

---

## How It Works

### Round Lifecycle

```
Day starts (00:00 UTC)
       │
       ▼
  [No round exists yet]
       │
       ▼  (first user participation)
  Round auto-created with default values
       │
       ▼
  Users claim free entries / buy entries
       │
       ▼  (admin decides to draw)
  Admin calls drawWinner() with off-chain random index
       │
       ▼
  Round finalized ─── Prize transferred to winner
       │
       ▼
  No more entries accepted for this round
```

- **Day ID** = `block.timestamp / 86400` (seconds in a day). Each day in UTC has a unique dayId.
- Rounds are **NOT** created manually. They auto-create when the first user participates (via `claimFreeEntry` or `buyEntry`).
- Once `drawWinner()` is called, the round is **finalized** and no more entries are accepted.

### Free Entries (EIP-712)

1. User requests a free entry from the backend.
2. Backend generates an EIP-712 signature for `FreeEntry(address account, uint256 dayId, uint256 nonce)`.
3. User calls `claimFreeEntry(signature)` on-chain.
4. Contract verifies the signature was signed by an address with `FREE_ENTRY_SIGNER_ROLE`.
5. User's entry is added to the round. The nonce increments to prevent replay.

**Key details:**
- Signatures are specific to: user address + dayId + nonce
- Nonce is per-user, per-day (resets each new day)
- Each signature can only be used once (nonce increments after each use)
- Free entries cost 0 FP tokens
- Limited by `maxFreeEntriesPerUser` per round (default: 1)
- Also limited by `maxEntriesPerUser` total cap
- User pays their own gas

**EIP-712 domain:**
```
name:    "DailyLottery"
version: "1"
chainId: (network chain ID)
verifyingContract: (proxy address)
```

**Type hash:**
```
FreeEntry(address account,uint256 dayId,uint256 nonce)
```

### Paid Entries

1. User must first approve the DailyLottery contract on FP1155 (`setApprovalForAll`).
2. User calls `buyEntry()`.
3. Contract transfers `entryPrice` FP tokens from user to contract via `agentTransferFrom`.
4. Contract immediately burns the received FP tokens.
5. Entry is added to the round.

**Key details:**
- Each call purchases exactly **1 entry**
- FP tokens are **burned immediately** (not held by the contract)
- Limited by `maxEntriesPerUser` total cap
- Free entries and paid entries share the same total cap
- `totalPaid` in the round tracks cumulative FP burned

### Winner Drawing

1. Admin generates a random number off-chain.
2. Admin calls `drawWinner(dayId, winningIndex, prizeData)`.
3. Contract selects `entries[dayId][winningIndex]` as the winner.
4. Prize is transferred from admin to winner.
5. Round is marked as finalized.

**Prize types:**

| Type | Token | Flow |
|------|-------|------|
| `PrizeType.FP` | FP1155 | Admin → Contract → Winner (via `agentTransferFrom`) |
| `PrizeType.ERC20` | Any ERC20 (USDT, USDC, POL, etc.) | Admin → Winner (via `safeTransferFrom`) |

**Requirements before calling `drawWinner`:**
- For FP prizes: Admin must have FP tokens and have approved the lottery contract (`setApprovalForAll`)
- For ERC20 prizes: Admin must have the ERC20 tokens and have approved the lottery contract (`approve`)

**Important:** `drawWinner` works even when the contract is paused. This allows finalizing rounds during emergency pauses.

---

## Configuration

### Default Values

Set at initialization and changeable via `setDefaults()`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `defaultSeasonId` | `324_001` | FP season ID used for burning entry fees |
| `defaultEntryPrice` | `1` | FP tokens burned per paid entry |
| `defaultMaxEntriesPerUser` | `10` | Maximum total entries (free + paid) per user per day |
| `defaultMaxFreeEntriesPerUser` | `1` | Maximum free entries per user per day |

Changing defaults only affects **future rounds** that haven't been created yet.

```solidity
// Example: Change defaults
lottery.setDefaults(
    324_002,  // new season ID
    2,        // 2 FP per entry
    15,       // max 15 entries per user
    3         // max 3 free entries per user
);
```

**Validations:**
- `entryPrice > 0`
- `maxEntriesPerUser > 0`
- `maxFreeEntriesPerUser > 0`
- `maxFreeEntriesPerUser <= maxEntriesPerUser`

### Per-Round Configuration

Once a round exists (auto-created), its parameters can be adjusted mid-round:

```solidity
lottery.updateRoundParameters(
    dayId,    // which round to update
    3,        // new entry price
    20,       // new max entries per user
    5         // new max free entries per user
);
```

**Restrictions:**
- Round must exist (cannot update non-existent rounds)
- Round must not be finalized
- Same validation rules as `setDefaults`
- Only `LOTTERY_ADMIN_ROLE` can call

---

## Data Structures

### PrizeType (Enum)

```solidity
enum PrizeType {
    FP,     // 0 - Prize is FP1155 tokens
    ERC20   // 1 - Prize is any ERC20 token
}
```

### PrizeData (Struct)

Used as input to `drawWinner()`:

```solidity
struct PrizeData {
    PrizeType prizeType;    // FP or ERC20
    address tokenAddress;   // ERC20 address (set address(0) for FP)
    uint256 seasonId;       // FP season ID (set 0 for ERC20)
    uint256 amount;         // Prize amount
}
```

### LotteryRound (Struct)

Complete state of one day's lottery:

```solidity
struct LotteryRound {
    uint256 dayId;                  // Day identifier
    uint256 seasonId;               // FP season for burning entry fees
    uint256 entryPrice;             // Cost per paid entry (in FP)
    uint256 maxEntriesPerUser;      // Max total entries per user
    uint256 maxFreeEntriesPerUser;  // Max free entries per user
    uint256 totalEntries;           // Total entries in the round
    uint256 totalPaid;              // Total FP burned for paid entries
    address winner;                 // Winner (address(0) if not drawn)
    bool finalized;                 // Whether winner has been drawn
    PrizeType prizeType;            // Prize type awarded
    address prizeTokenAddress;      // ERC20 prize address (address(0) for FP)
    uint256 prizeSeasonId;          // FP prize season (0 for ERC20)
    uint256 prizeAmount;            // Prize amount awarded
}
```

### Storage Mappings

```solidity
mapping(uint256 => LotteryRound) lotteryRounds;           // dayId => round
mapping(uint256 => mapping(address => uint256)) userEntries; // dayId => user => entry count
mapping(uint256 => address[]) entries;                      // dayId => [user addresses]
mapping(uint256 => mapping(address => uint256)) nonces;     // dayId => user => free entry nonce
```

The `entries` array is the "ticket pool" - each entry pushes the user's address once. A user with 3 entries has their address 3 times. The `winningIndex` picks from this array.

---

## Events

```solidity
// Emitted when a round is auto-created
event LotteryRoundCreated(
    uint256 indexed dayId, uint256 seasonId, uint256 entryPrice,
    uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
);

// Emitted when a user claims a free entry
event FreeEntryGranted(address indexed user, uint256 indexed dayId, uint256 nonce);

// Emitted when a user buys an entry
event EntryPurchased(address indexed user, uint256 indexed dayId, uint256 entriesPurchased);

// Emitted when a winner is drawn
event WinnerDrawn(
    uint256 indexed dayId, address indexed winner, PrizeType prizeType,
    address tokenAddress, uint256 seasonId, uint256 amount
);

// Emitted when default configuration changes
event DefaultsUpdated(
    uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
);

// Emitted when a specific round's parameters are updated
event RoundParametersUpdated(
    uint256 indexed dayId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
);
```

---

## View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getCurrentDayId()` | `uint256` | Current day ID (`block.timestamp / 1 days`) |
| `getLotteryRound(dayId)` | `LotteryRound` | Full round data. If round doesn't exist, `dayId` field = 0 |
| `getUserEntries(dayId, user)` | `uint256` | Total entries (free + paid) for user on that day |
| `getUserNonce(dayId, user)` | `uint256` | Free entries claimed by user (= nonce value) |
| `getEntry(dayId, index)` | `address` | User address at specific entry index |
| `getTotalEntries(dayId)` | `uint256` | Total entries in the round |
| `getRemainingEntries(dayId, user)` | `(uint256, uint256)` | `(remainingFreeEntries, remainingTotalEntries)`. Uses defaults if round doesn't exist |
| `DOMAIN_SEPARATOR()` | `bytes32` | EIP-712 domain separator for client-side signing |

---

## Deployment

### Initial Deployment

**Script:** `script/DeployDailyLottery.s.sol:DeployDailyLottery`

**Required environment variables:**
```bash
PRIVATE_KEY=0x...          # Deployer private key (gets DEFAULT_ADMIN_ROLE)
FP1155_ADDRESS=0x...       # Existing FP1155 proxy address
LOTTERY_ADMIN_ADDRESS=0x...# Gets LOTTERY_ADMIN_ROLE + FREE_ENTRY_SIGNER_ROLE
```

**Command:**
```bash
forge script script/DeployDailyLottery.s.sol:DeployDailyLottery \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

This deploys:
1. `DailyLottery` implementation contract
2. `ERC1967Proxy` pointing to the implementation, initialized with `initialize()`

### Post-Deployment Setup

**Script:** `script/DeployDailyLottery.s.sol:SetupDailyLottery`

**Required environment variables:**
```bash
PRIVATE_KEY=0x...                       # Admin private key (must have DEFAULT_ADMIN_ROLE on FP1155)
FP1155_ADDRESS=0x...                    # FP1155 proxy address
LOTTERY_ADDRESS=0x...                   # DailyLottery proxy address
LOTTERY_FREE_ENTRY_SIGNER_ADDRESS=0x... # Backend signer address (if different from lottery admin)
```

**Command:**
```bash
forge script script/DeployDailyLottery.s.sol:SetupDailyLottery \
  --rpc-url <RPC_URL> \
  --broadcast
```

**What it does:**
1. Grants `TRANSFER_AGENT_ROLE` to the DailyLottery contract on FP1155 (required for `agentTransferFrom` and `burn`)

**Manual steps after setup (if needed):**
- Grant `FREE_ENTRY_SIGNER_ROLE` to additional backend signers:
  ```solidity
  lottery.grantRole(FREE_ENTRY_SIGNER_ROLE, backendSignerAddress);
  ```
- Grant `TRANSFER_AGENT_ROLE` to the lottery admin on FP1155 (if admin will provide FP prizes):
  ```solidity
  fpToken.grantRole(TRANSFER_AGENT_ROLE, adminAddress);
  ```

### Upgrading

**Script:** `script/UpgradeDailyLottery.s.sol:UpgradeDailyLottery`

**Required environment variables:**
```bash
PRIVATE_KEY=0x...       # Must have DEFAULT_ADMIN_ROLE
LOTTERY_ADDRESS=0x...   # Existing proxy address
```

**Command:**
```bash
LOTTERY_ADDRESS=0x... forge script script/UpgradeDailyLottery.s.sol:UpgradeDailyLottery \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

**Verify new implementation manually (if needed):**
```bash
BSCSCAN_API_KEY=<KEY> forge verify-contract <NEW_IMPL_ADDRESS> src/DailyLottery.sol:DailyLottery --chain bsc-testnet
```

---

## Integration with FP1155

The DailyLottery contract depends on `FP1155` for:

1. **Burning entry fees:** `agentTransferFrom(user, contract, seasonId, price, "")` + `burn(contract, seasonId, price)`
2. **Transferring FP prizes:** `agentTransferFrom(admin, contract, ...)` + `agentTransferFrom(contract, winner, ...)`

**Required roles on FP1155:**

| Who | Role on FP1155 | Why |
|-----|---------------|-----|
| DailyLottery contract | `TRANSFER_AGENT_ROLE` | To call `agentTransferFrom` and `burn` |
| Lottery admin (if providing FP prizes) | `TRANSFER_AGENT_ROLE` | To allow `agentTransferFrom` from admin to contract |

**Required approvals:**

| Who | Approves What | Why |
|-----|--------------|-----|
| Users | `fpToken.setApprovalForAll(lotteryAddress, true)` | Allow lottery to transfer FP for paid entries |
| Admin | `fpToken.setApprovalForAll(lotteryAddress, true)` | Allow lottery to transfer FP for prizes |
| Admin | `erc20Token.approve(lotteryAddress, amount)` | Allow lottery to transfer ERC20 for prizes |

---

## Backend Integration Guide

### Generating Free Entry Signatures

The backend must sign EIP-712 typed data to authorize free entries. Here's the signing flow:

**1. Get required data:**
```typescript
const dayId = await lottery.getCurrentDayId();
const nonce = await lottery.getUserNonce(dayId, userAddress);
```

**2. Build EIP-712 typed data:**
```typescript
const domain = {
  name: "DailyLottery",
  version: "1",
  chainId: 97,  // BSC testnet (56 for mainnet)
  verifyingContract: LOTTERY_PROXY_ADDRESS,
};

const types = {
  FreeEntry: [
    { name: "account", type: "address" },
    { name: "dayId", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ],
};

const value = {
  account: userAddress,
  dayId: dayId,
  nonce: nonce,
};
```

**3. Sign with the backend signer wallet:**
```typescript
const signature = await signerWallet.signTypedData(domain, types, value);
```

**4. Return the signature to the user.** The user calls `claimFreeEntry(signature)` on-chain.

### Drawing a Winner

**1. Get round data:**
```typescript
const dayId = targetDayId; // or await lottery.getCurrentDayId()
const totalEntries = await lottery.getTotalEntries(dayId);
```

**2. Generate random index off-chain:**
```typescript
const winningIndex = Math.floor(Math.random() * Number(totalEntries));
// In production, use a secure random source (e.g., Chainlink VRF result, server-side CSPRNG)
```

**3. Prepare prize and approvals:**

For FP prize:
```typescript
// Admin must have FP tokens and approval
await fpToken.setApprovalForAll(lotteryAddress, true); // if not already approved

const prizeData = {
  prizeType: 0,             // FP
  tokenAddress: ethers.ZeroAddress,
  seasonId: 324_001,
  amount: 1000,
};
```

For ERC20 prize:
```typescript
// Admin must have tokens and approval
await usdtToken.approve(lotteryAddress, prizeAmount);

const prizeData = {
  prizeType: 1,             // ERC20
  tokenAddress: USDT_ADDRESS,
  seasonId: 0,
  amount: ethers.parseUnits("100", 18), // depends on token decimals
};
```

**4. Call drawWinner:**
```typescript
await lottery.drawWinner(dayId, winningIndex, prizeData);
```

---

## TypeScript Tools

### `tools/lottery/buy-entry.ts`

Script for buying a lottery entry from the CLI.

```bash
# Basic usage
ts-node tools/lottery/buy-entry.ts

# With options
ts-node tools/lottery/buy-entry.ts --contract 0x... --rpc https://...
```

**Env vars:** `USER_PK`, `LOTTERY_ADDRESS`, `FP_TOKEN_ADDRESS`, `TESTNET_BSC_RPC_URL`

### `tools/lottery/view-entries.ts`

Script for viewing lottery round info and entries.

```bash
# View today's round
ts-node tools/lottery/view-entries.ts

# View specific day
ts-node tools/lottery/view-entries.ts --dayId 20505

# Choose network
ts-node tools/lottery/view-entries.ts --network mainnet
ts-node tools/lottery/view-entries.ts --network testnet
```

**Env vars:** `LOTTERY_ADDRESS`, `MAINNET_BSC_RPC_URL`, `TESTNET_BSC_RPC_URL`

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Reentrancy | `ReentrancyGuardUpgradeable` on all state-changing functions |
| Signature replay | Per-day, per-user nonce prevents reuse of signatures |
| Unauthorized access | Role-based access control for all admin functions |
| Emergency stop | `Pausable` stops user participation; admin can still draw winners |
| Randomness manipulation | Randomness is generated off-chain (not on-chain) |
| ERC20 transfer safety | Uses OpenZeppelin `SafeERC20` for all ERC20 transfers |
| Upgrade safety | Only `DEFAULT_ADMIN_ROLE` can upgrade; 50-slot storage gap reserved |
| Invalid signatures | `ECDSA.recover` + role check on recovered signer address |

**Note on randomness:** The winning index is provided by the admin. This is a trust assumption - the admin (or the backend service) is trusted to generate a fair random number. For verifiable randomness, consider integrating Chainlink VRF in the future.

---

## Test Coverage

**Test file:** `test/DailyLottery.t.sol`

| Category | Tests | What's covered |
|----------|-------|----------------|
| Initialization | 1 | Default values, roles, FP token reference |
| Round Auto-Creation | 6 | Auto-create on first entry, setDefaults validations |
| Free Entries | 6 | Valid signatures, invalid signatures, wrong day, multiple free entries, max exceeded, buy after max free |
| Paid Entries | 6 | Buy entry, max entries, exceed max, without free entry, free after buying |
| Winner Drawing | 6 | FP prizes, ERC20 prizes (USDT, USDC, POL), no entries, already finalized, invalid index, works while paused |
| Multi-Day | 1 | Separate state per day, nonce resets |
| View Functions | 8 | getCurrentDayId, getEntry, getRemainingEntries (various states), custom defaults, non-existent round |
| Pause/Unpause | 4 | Pause blocks entries, unpause allows entries, unauthorized pause/unpause |
| Round Parameters | 5 | Update price mid-round, update limits, non-existent round, finalized round, invalid params, unauthorized |

**Run tests:**
```bash
forge test --match-contract DailyLotteryTest -vv
```

---

## FAQ

**Q: What happens if no one enters the lottery for a day?**
A: No round is created. The admin cannot call `drawWinner` because the round doesn't exist (`"Lottery not active"` error).

**Q: Can the admin draw a winner for a past day?**
A: Yes, as long as the round exists, is not finalized, and has entries. There's no time restriction on when `drawWinner` can be called.

**Q: Can a user participate in multiple days simultaneously?**
A: Yes. Each day has independent state. A user can have entries on day N while day N-1 is still unfinalized.

**Q: What FP season is used for burning entries vs. prizes?**
A: The `seasonId` in the round (from defaults) determines which FP tokens are burned for entries. The prize `seasonId` is independent and set when calling `drawWinner`.

**Q: Can the prize amount be zero?**
A: No. `drawWinner` requires `prize.amount > 0`.

**Q: What if the admin doesn't have enough tokens for the prize?**
A: The `drawWinner` transaction will revert because the token transfer will fail.

**Q: Can the entry price be changed after users have already bought entries?**
A: Yes, via `updateRoundParameters`. Existing entries are not affected. New entries will use the updated price.

**Q: How do I check if a round exists?**
A: Call `getLotteryRound(dayId)`. If `round.dayId == 0`, the round doesn't exist yet.

**Q: How does the entries array work for winner selection?**
A: Each entry (free or paid) pushes the user's address into the `entries[dayId]` array. If user1 has 3 entries, their address appears 3 times. The `winningIndex` selects one position, so more entries = higher probability of winning.

**Q: Can the contract hold funds?**
A: The contract never holds FP tokens (they're burned immediately). For ERC20 prizes, tokens go directly from admin to winner. The contract only briefly holds FP tokens during prize distribution (admin → contract → winner in the same transaction).
