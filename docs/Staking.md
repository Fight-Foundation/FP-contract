# Staking Contract

## Overview

Staking is a **minimal FIGHT token staking contract**. Users stake ERC-20 FIGHT tokens, and all reward/weight calculations happen off-chain using event data. There are no lock periods, no on-chain rewards, and no slashing. It's designed for simplicity, security, and gas efficiency.

**Contract:** `src/Staking.sol`
**Network:** BSC (Testnet & Mainnet)
**Pattern:** Non-upgradeable (direct deployment, no proxy)
**Solidity:** ^0.8.20
**Dependencies:** OpenZeppelin Contracts v5 (non-upgradeable)

---

## Table of Contents

- [Architecture](#architecture)
- [How Staking Works](#how-staking-works)
- [State Variables](#state-variables)
- [Functions](#functions)
  - [User Functions](#user-functions)
  - [Owner Functions](#owner-functions)
- [Events](#events)
- [Off-Chain Weight Calculation](#off-chain-weight-calculation)
- [Token Recovery](#token-recovery)
- [Deployment](#deployment)
- [TypeScript Tools](#typescript-tools)
- [Security Considerations](#security-considerations)
- [Test Coverage](#test-coverage)
- [FAQ](#faq)

---

## Architecture

```
              ┌─────────────────┐
              │    Staking      │  (non-upgradeable, direct deploy)
              │                 │
              │  Ownable2Step   │  (2-step ownership transfer)
              │  Pausable       │  (emergency pause)
              │  ReentrancyGuard│  (reentrancy protection)
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  FIGHT Token    │  (ERC-20)
              │  (immutable)    │
              └─────────────────┘
```

**Key design choice:** Non-upgradeable. If changes are needed, deploy a new contract and coordinate migration.

---

## How Staking Works

```
User has FIGHT tokens
       │
       ▼  approve(stakingAddress, amount)
User approves Staking contract on FIGHT token
       │
       ▼  stake(amount)
FIGHT tokens transferred from user → Staking contract
       │
       ▼
Off-chain systems track staking events for reward calculations
       │
       ▼  unstake(amount)   (no lock period, immediate)
FIGHT tokens transferred from Staking contract → user
```

**No on-chain rewards.** The contract only holds tokens and emits events. All reward logic (APY, weight, distribution) lives off-chain.

---

## State Variables

```solidity
IERC20 public immutable FIGHT_TOKEN;            // FIGHT token address (set once, never changes)
uint256 public totalStaked;                      // Total FIGHT staked across all users
mapping(address => uint256) public balances;     // Per-user staked balance
```

---

## Functions

### User Functions

#### `stake(uint256 amount)`

Stakes FIGHT tokens into the contract.

- **Modifiers:** `whenNotPaused`, `nonReentrant`
- **Requirements:** `amount > 0`, user must have approved the contract, user must have sufficient balance
- **Effects:** Increments `balances[user]` and `totalStaked`, transfers tokens from user to contract
- **Note:** Can be called multiple times to increase stake

#### `unstake(uint256 amount)`

Withdraws staked FIGHT tokens.

- **Modifiers:** `nonReentrant` (NOT `whenNotPaused` — users can always exit)
- **Requirements:** `amount > 0`, `balances[user] >= amount`
- **Effects:** Decrements `balances[user]` and `totalStaked`, transfers tokens to user
- **No lock period** — immediate withdrawal at any time, even when paused

### Owner Functions

#### `pause()` / `unpause()`

- `pause()` blocks `stake()` but NOT `unstake()` (users can always exit)
- Only callable by owner

#### `renounceOwnership()`

- **Overridden to revert** with `"Not allowed"`
- Prevents accidentally losing pause/unpause capability

#### `recoverERC20(address token, address to, uint256 amount)`

Recovers accidentally sent ERC-20 tokens (NOT FIGHT tokens).

- **Cannot** recover FIGHT_TOKEN (protects user stakes)
- Only callable by owner

#### `recoverFightSurplus(address to)`

Recovers FIGHT tokens sent directly to the contract (not via `stake()`).

- Calculates `surplus = contractBalance - totalStaked`
- Only transfers the surplus — user stakes are **never** at risk
- Reverts with `"No surplus"` if no excess exists

---

## Events

```solidity
event Staked(
    address indexed user,
    uint256 amount,
    uint256 userBalanceBefore,
    uint256 userBalanceAfter,
    uint256 totalStakedAfter,
    uint256 timestamp,
    uint256 blockNumber
);

event Unstaked(
    address indexed user,
    uint256 amount,
    uint256 userBalanceBefore,
    uint256 userBalanceAfter,
    uint256 totalStakedAfter,
    uint256 timestamp,
    uint256 blockNumber
);

event RecoveredERC20(address indexed token, address indexed to, uint256 amount);
event RecoveredFightSurplus(address indexed to, uint256 amount);
```

Events include `timestamp` and `blockNumber` specifically to enable off-chain weight calculations.

---

## Off-Chain Weight Calculation

The contract emits rich events with before/after snapshots. Off-chain indexers use this data to calculate rewards:

**Example:**
```
Block 1000: User stakes 100 FIGHT   → balanceAfter=100, totalStakedAfter=100
Block 2000: User stakes 50 more     → balanceAfter=150, totalStakedAfter=150
Block 3000: User unstakes 100       → balanceAfter=50,  totalStakedAfter=50
```

An indexer can reconstruct:
- User had 100 tokens for blocks 1000-2000 (1000 blocks)
- User had 150 tokens for blocks 2000-3000 (1000 blocks)
- User has 50 tokens from block 3000 onward
- Weighted stake = (100 * 1000) + (150 * 1000) + (50 * N) = ...

This allows flexible reward formulas without on-chain gas costs.

---

## Token Recovery

Two separate recovery mechanisms protect against different scenarios:

| Scenario | Function | Safety |
|----------|----------|--------|
| Someone sends random ERC-20 tokens to the contract | `recoverERC20(token, to, amount)` | Cannot recover FIGHT_TOKEN |
| Someone sends FIGHT tokens directly (not via `stake()`) | `recoverFightSurplus(to)` | Only recovers `balance - totalStaked` |

Both are owner-only and mathematically guarantee user stakes are never at risk.

---

## Deployment

### Deploy Script

**Script:** `script/DeployStaking.s.sol:DeployStaking`

**Required env vars:**
```bash
PRIVATE_KEY=0x...            # Deployer (becomes owner)
FIGHT_TOKEN_ADDRESS=0x...    # FIGHT ERC-20 token address
```

**Command:**
```bash
forge script script/DeployStaking.s.sol:DeployStaking \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

**Validations:**
- Verifies `FIGHT_TOKEN_ADDRESS` has code (is a deployed contract)
- Deployer becomes the owner

### Post-Deployment

No additional setup required. Users just need to:
1. `FIGHT_TOKEN.approve(stakingAddress, amount)`
2. `staking.stake(amount)`

---

## TypeScript Tools

Located in `tools/staking/`:

### `stake.ts` — Stake, Unstake, Check Balance

```bash
# Stake tokens
ts-node tools/staking/stake.ts --network testnet --action stake --amount 100

# Unstake tokens
ts-node tools/staking/stake.ts --network testnet --action unstake --amount 50

# Check balance
ts-node tools/staking/stake.ts --network testnet --action balance
```

**Env vars:** `USER_PK`, `TESTNET_STAKING_ADDRESS` / `MAINNET_STAKING_ADDRESS`, `TESTNET_FIGHT_TOKEN_ADDRESS` / `MAINNET_FIGHT_TOKEN_ADDRESS`

Auto-approves if needed (approves 2x amount to minimize re-approvals).

### `mint-fight.ts` — Mint FIGHT Tokens (Testing)

```bash
# Mint 1M tokens to an address
ts-node tools/staking/mint-fight.ts --network testnet --to 0x... --amount 1000000
```

**Env vars:** `PRIVATE_KEY` (must have minter role on FIGHT token)

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Reentrancy | `nonReentrant` on both `stake` and `unstake` |
| Fund drainage | `recoverERC20` blocks FIGHT_TOKEN; `recoverFightSurplus` only takes excess |
| Ownership loss | `renounceOwnership()` disabled (reverts) |
| User exit during emergency | `unstake()` works even when paused |
| Ownership transfer safety | Uses `Ownable2Step` (requires acceptance) |
| Invalid token | Constructor validates `fightToken.code.length > 0` |

---

## Test Coverage

**Test file:** `test/Staking.t.sol` (~40+ tests)

| Category | Tests |
|----------|-------|
| Staking | Basic stake, events, multiple users, zero amount, paused, insufficient allowance/balance |
| Unstaking | Basic unstake, partial, events, works when paused, zero amount, insufficient balance |
| Pause | Only owner, non-owner reverts, pause/unpause cycle |
| Reentrancy | Attack simulations on stake and unstake |
| Getters | Balance, token address, totalStaked updates |
| Integration | Full multi-user lifecycle |
| Ownership | renounceOwnership reverts, non-owner checks |
| Recovery | ERC20 recovery, surplus recovery, cannot recover FIGHT, no surplus revert, zero address checks |

```bash
forge test --match-contract StakingTest -vv
```

---

## FAQ

**Q: Are there lock periods?**
A: No. Users can unstake immediately, at any time, even when the contract is paused.

**Q: How are rewards distributed?**
A: Off-chain. The contract only stores tokens and emits events. External systems index the events to calculate and distribute rewards.

**Q: Can the owner drain user stakes?**
A: No. `recoverERC20` cannot touch FIGHT tokens. `recoverFightSurplus` can only take tokens that exceed `totalStaked` (surplus). User stakes are mathematically protected.

**Q: Is this contract upgradeable?**
A: No. It's a direct deployment. If changes are needed, deploy a new contract. Users would need to unstake from the old contract and stake in the new one.

**Q: Why is `renounceOwnership` disabled?**
A: To ensure the owner always retains the ability to pause the contract in emergencies. Without an owner, the contract could never be paused.

**Q: What token is staked?**
A: FIGHT (an ERC-20 token). This is different from FP (which is ERC-1155). The FIGHT token address is set in the constructor and is immutable.
