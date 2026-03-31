# Booster Contract

## Overview

Booster is the **UFC Strike Now pick'em** prediction system. Users stake FP tokens on fight predictions (winner + method), and winners split the prize pool proportionally based on their accuracy. It manages events with multiple fights, handles FP token staking, result submission, and reward distribution.

**Contract:** `src/Booster.sol` (1252 lines)
**Network:** BSC (Testnet & Mainnet)
**Pattern:** UUPS Upgradeable Proxy (ERC1967Proxy)
**Solidity:** ^0.8.20
**Dependencies:** OpenZeppelin Contracts Upgradeable v5, FP1155

---

## Table of Contents

- [Architecture](#architecture)
- [Roles & Access Control](#roles--access-control)
- [Data Structures](#data-structures)
- [How Boosting Works](#how-boosting-works)
  - [Full Lifecycle](#full-lifecycle)
  - [Prize Pool Formula](#prize-pool-formula)
  - [Points Calculation](#points-calculation)
  - [Cancelled Fights](#cancelled-fights)
- [Operator Functions](#operator-functions)
  - [Event Management](#event-management)
  - [Fight Management](#fight-management)
  - [Result Submission](#result-submission)
  - [Claim Management](#claim-management)
  - [Bonus Deposits](#bonus-deposits)
  - [Purging Unclaimed Funds](#purging-unclaimed-funds)
- [User Functions](#user-functions)
- [View Functions](#view-functions)
- [Configuration](#configuration)
- [Events](#events)
- [Deployment](#deployment)
- [Integration with FP1155](#integration-with-fp1155)
- [TypeScript Tools](#typescript-tools)
- [Security Considerations](#security-considerations)
- [Test Coverage](#test-coverage)
- [FAQ](#faq)

---

## Architecture

```
                    ┌─────────────────────┐
                    │    ERC1967Proxy      │
                    └─────────┬───────────┘
                              │ delegatecall
                    ┌─────────▼───────────┐
                    │      Booster         │
                    │                     │
                    │  AccessControl       │
                    │  ReentrancyGuard     │
                    │  UUPSUpgradeable     │
                    │  IERC1155Receiver    │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │      FP1155          │
                    │  (agentTransferFrom) │
                    └─────────────────────┘
```

**Storage gap:** `uint256[50] private __gap` reserved for future upgrades.

---

## Roles & Access Control

| Role | Capabilities |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Upgrade contract, update FP1155 address, manage roles |
| `OPERATOR_ROLE` | Create events, manage fights, submit results, deposit bonuses, configure limits, purge unclaimed funds |

---

## Data Structures

### Enums

```solidity
enum FightStatus { OPEN, CLOSED, RESOLVED }
enum WinMethod   { KNOCKOUT, SUBMISSION, DECISION, NO_CONTEST }
enum Corner      { RED, BLUE, NONE }
```

### Event Struct

```solidity
struct Event {
    uint256 seasonId;       // FP season this event uses
    uint256 numFights;      // Fights numbered 1..numFights
    bool exists;
    uint256 claimDeadline;  // Unix timestamp (0 = no limit)
    bool claimReady;        // Final lock: results immutable, claims enabled
}
```

### Fight Struct

```solidity
struct Fight {
    FightStatus status;
    Corner winner;
    WinMethod method;
    uint256 bonusPool;              // Operator-deposited bonus FP
    uint256 originalPool;           // Sum of all user boost stakes
    uint256 sumWinnersStakes;       // Sum of winning users' stakes
    uint256 winningPoolTotalShares; // Sum of (points * stake) for all winners
    uint256 pointsForWinner;        // Points for correct winner only
    uint256 pointsForWinnerMethod;  // Points for correct winner AND method
    uint256 claimedAmount;          // Total claimed from pool so far
    uint256 boostCutoff;            // Unix timestamp cutoff for new boosts (0 = status only)
    bool cancelled;                 // Cancelled/no-contest (enables full refund)
}
```

### Boost Struct

```solidity
struct Boost {
    address user;
    uint256 amount;               // FP staked (can be increased via addToBoost)
    Corner predictedWinner;
    WinMethod predictedMethod;
    bool claimed;
}
```

### Input Structs (for batching)

```solidity
struct BoostInput { uint256 fightId; uint256 amount; Corner predictedWinner; WinMethod predictedMethod; }
struct ClaimInput { uint256 fightId; uint256[] boostIndices; }
struct FightResultInput { uint256 fightId; Corner winner; WinMethod method; uint256 pointsForWinner;
                          uint256 pointsForWinnerMethod; uint256 sumWinnersStakes; uint256 winningPoolTotalShares; }
```

### Storage Mappings

```solidity
mapping(string => Event) events;                                          // eventId => Event
mapping(string => mapping(uint256 => Fight)) fights;                      // eventId => fightId => Fight
mapping(string => mapping(uint256 => Boost[])) boosts;                    // eventId => fightId => Boost[]
mapping(string => mapping(uint256 => mapping(address => uint256[])))
    userBoostIndices;                                                     // eventId => fightId => user => indices
```

---

## How Boosting Works

### Full Lifecycle

```
1. OPERATOR creates event
   createEvent("UFC_300", 12, 324_001, cutoffTimestamp)
       │
2. Users place boosts (predictions)
   placeBoosts("UFC_300", [{ fightId: 1, amount: 100, predictedWinner: RED, predictedMethod: KNOCKOUT }])
       │  FP transferred from user to Booster contract
       │
3. Fights happen (OPERATOR closes fights)
   updateFightStatus("UFC_300", 1, CLOSED)
       │
4. OPERATOR submits results
   submitFightResult("UFC_300", 1, RED, KNOCKOUT, 100, 200, 5000, 1000000)
       │  fight.status = RESOLVED
       │
5. OPERATOR enables claims
   setEventClaimReady("UFC_300", true)
       │  Results locked, claims enabled
       │
6. Users claim rewards
   claimReward("UFC_300", 1, [0, 1, 2])
       │  FP transferred from Booster back to user
       │
7. (Optional) After deadline, sweep unclaimed
   purgeEvent("UFC_300", recipientAddress)
```

### Prize Pool Formula

For each winning boost:

```
prizePool = fight.originalPool - fight.sumWinnersStakes + fight.bonusPool
userShares = points * boost.amount
winnings = (prizePool * userShares) / fight.winningPoolTotalShares
payout = boost.amount + winnings  (stake returned + winnings)
```

**Explanation:**
- `originalPool` = all user stakes in this fight
- `sumWinnersStakes` = stakes belonging to winning users (returned to them)
- `bonusPool` = operator-deposited extra FP
- The losers' stakes + bonus become the prize pool
- Winners get their original stake back **plus** a proportional share of the prize pool

### Points Calculation

```solidity
function calculateUserPoints(
    Corner predictedWinner, WinMethod predictedMethod,
    Corner actualWinner, WinMethod actualMethod,
    uint256 pointsForWinner, uint256 pointsForWinnerMethod
) returns (uint256)
```

| Prediction | Points |
|-----------|--------|
| Wrong winner | 0 (loses stake) |
| Correct winner, wrong method | `pointsForWinner` |
| Correct winner AND method | `pointsForWinnerMethod` (must be >= pointsForWinner) |

Users who predicted both winner and method correctly get more shares of the prize pool.

### Cancelled Fights

When a fight is cancelled (or `Corner.NONE` + `NO_CONTEST` is submitted):
- `fight.cancelled = true`
- All users get a **full refund** of their original stake
- No winnings are distributed
- Users still need to call `claimReward()` to receive the refund

---

## Operator Functions

### Event Management

```solidity
// Create event with fights
createEvent(eventId, numFights, seasonId, defaultBoostCutoff)

// Set claim deadline (non-decreasing)
setEventClaimDeadline(eventId, deadline)

// Lock results and enable claims
setEventClaimReady(eventId, true)
```

### Fight Management

```solidity
// Status transitions: OPEN -> CLOSED -> RESOLVED (forward only)
updateFightStatus(eventId, fightId, newStatus)

// Set boost cutoff per fight
setFightBoostCutoff(eventId, fightId, cutoffTimestamp)

// Set boost cutoff for all non-resolved fights in event
setEventBoostCutoff(eventId, cutoffTimestamp)

// Cancel fight (full refund to all users)
cancelFight(eventId, fightId)
```

### Result Submission

```solidity
// Single fight result
submitFightResult(eventId, fightId, winner, method,
    pointsForWinner, pointsForWinnerMethod, sumWinnersStakes, winningPoolTotalShares)

// Batch results
submitFightResults(eventId, FightResultInput[])
```

**Validations:**
- `pointsForWinner > 0`
- `pointsForWinnerMethod >= pointsForWinner`
- `Corner.NONE` requires `WinMethod.NO_CONTEST` (auto-sets cancelled=true)
- `sumWinnersStakes <= fight.originalPool`
- Cannot update if `claimReady == true`
- Results CAN be updated multiple times until `claimReady` is set

### Claim Management

```solidity
setEventClaimReady(eventId, true)   // Lock results, enable claims
setEventClaimReady(eventId, false)  // Unlock results (emergency only, not normal flow)
```

### Bonus Deposits

```solidity
// Deposit FP bonus to fight prize pool
depositBonus(eventId, fightId, amount, force)
```

- `force=true` allows deposit even on RESOLVED fights (for corrections)
- Operator must have FP tokens (transferred via `agentTransferFrom`)
- Respects `maxBonusDeposit` limit

### Purging Unclaimed Funds

```solidity
// After claim deadline passes, sweep all unclaimed FP
purgeEvent(eventId, recipientAddress)
```

- Only works after `claimDeadline` has passed
- Iterates all resolved fights, calculates unclaimed amounts
- Transfers total unclaimed FP to recipient

---

## User Functions

### Placing Boosts

```solidity
// Place one or more boosts in a single transaction
placeBoosts(eventId, BoostInput[])
```

- Fight must be OPEN and not past boostCutoff
- Each amount must be >= `minBoostAmount`
- FP transferred in a single batch from user to contract
- Creates separate Boost entries per fight

### Increasing a Boost

```solidity
// Add more FP to an existing boost
addToBoost(eventId, fightId, boostIndex, additionalAmount)
```

- Same validations as placeBoosts
- Must be the boost owner
- Cannot change prediction, only increase amount

### Claiming Rewards

```solidity
// Claim for one fight
claimReward(eventId, fightId, boostIndices)

// Claim across multiple fights
claimRewards(eventId, ClaimInput[])
```

- Event must be `claimReady`
- Claim deadline must not have passed
- Only winning boosts get paid (losing boosts revert with "boost did not win")
- Cancelled fights: full refund of stake

---

## View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getEvent(eventId)` | `(seasonId, numFights, exists, claimReady)` | Event details |
| `getEventClaimDeadline(eventId)` | `uint256` | Claim deadline timestamp |
| `isEventClaimReady(eventId)` | `bool` | Whether claims are enabled |
| `getEventFights(eventId)` | `(fightIds[], statuses[])` | All fights with statuses |
| `getFight(eventId, fightId)` | All fight fields | Complete fight state |
| `totalPool(eventId, fightId)` | `uint256` | originalPool + bonusPool |
| `getUserBoosts(eventId, fightId, user)` | `Boost[]` | User's boosts for a fight |
| `getUserBoostIndices(eventId, fightId, user)` | `uint256[]` | Indices into the fight's boost array |
| `quoteClaimable(eventId, fightId, user, enforceDeadline)` | `uint256` | How much user can claim (unclaimed only) |
| `quoteClaimableHistorical(eventId, fightId, user)` | `uint256` | Total including already claimed (for analysis) |
| `calculateUserPoints(predicted, actual, ...)` | `uint256` | Points for a given prediction vs result |

---

## Configuration

Set by `OPERATOR_ROLE`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `minBoostAmount` | `0` (disabled) | Minimum FP per boost. Set > 0 to prevent dust boosts |
| `maxFightsPerEvent` | `20` | Max fights per event. `0` = unlimited |
| `maxBonusDeposit` | `0` (unlimited) | Max FP per single bonus deposit |

```solidity
booster.setMinBoostAmount(1000);
booster.setMaxFightsPerEvent(15);
booster.setMaxBonusDeposit(50000);
```

Set by `DEFAULT_ADMIN_ROLE`:

```solidity
// Update FP1155 reference (if contract is redeployed)
booster.setFP(newFP1155Address);
```

---

## Events

```solidity
event EventCreated(string indexed eventId, uint256 numFights, uint256 indexed seasonId);
event EventClaimDeadlineUpdated(string indexed eventId, uint256 deadline);
event EventClaimReady(string indexed eventId, bool claimReady);
event FightStatusUpdated(string indexed eventId, uint256 indexed fightId, FightStatus status);
event FightBoostCutoffUpdated(string indexed eventId, uint256 indexed fightId, uint256 cutoff);
event FightCancelled(string indexed eventId, uint256 indexed fightId);
event MinBoostAmountUpdated(uint256 oldAmount, uint256 newAmount);
event MaxFightsPerEventUpdated(uint256 oldLimit, uint256 newLimit);
event MaxBonusDepositUpdated(uint256 oldLimit, uint256 newLimit);
event BonusDeposited(string indexed eventId, uint256 indexed fightId, address indexed manager, uint256 amount);
event BoostPlaced(string indexed eventId, uint256 indexed fightId, address indexed user,
    uint256 boostIndex, uint256 amount, Corner winner, WinMethod method, uint256 timestamp);
event BoostIncreased(string indexed eventId, uint256 indexed fightId, address indexed user,
    uint256 boostIndex, uint256 additionalAmount, uint256 newTotal, uint256 timestamp);
event FightResultSubmitted(string indexed eventId, uint256 indexed fightId, Corner indexed winner,
    WinMethod method, uint256 pointsForWinner, uint256 pointsForWinnerMethod,
    uint256 sumWinnersStakes, uint256 winningPoolTotalShares);
event RewardClaimed(string indexed eventId, uint256 indexed fightId, address indexed user,
    uint256 boostIndex, uint256 payout, uint256 points);
event EventPurged(string indexed eventId, address indexed recipient, uint256 amount);
event FightPurged(string indexed eventId, uint256 indexed fightId, uint256 unclaimedPool);
event FPUpdated(address indexed oldFP, address indexed newFP);
```

---

## Deployment

### Initial Deployment

**Script:** `script/DeployBooster.s.sol`

**Required env vars:**
```bash
PRIVATE_KEY=0x...           # Deployer (gets DEFAULT_ADMIN_ROLE)
FP1155_ADDRESS=0x...        # Existing FP1155 proxy address
OPERATOR_ADDRESS=0x...      # Optional (defaults to deployer)
```

**Command:**
```bash
forge script script/DeployBooster.s.sol \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

**The deploy script also:**
1. Grants `TRANSFER_AGENT_ROLE` to Booster on FP1155
2. Grants `OPERATOR_ROLE` to operator address

### Upgrading

**Script:** `script/UpgradeBooster.s.sol`

```bash
forge script script/UpgradeBooster.s.sol \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

---

## Integration with FP1155

**Required roles on FP1155:**

| Who | Role | Why |
|-----|------|-----|
| Booster contract | `TRANSFER_AGENT_ROLE` | Call `agentTransferFrom` for boost staking and reward payouts |
| Operator (if depositing bonus) | Allowlisted or `TRANSFER_AGENT_ROLE` | Allow FP transfer for bonus deposits |

**Token flow:**
```
User places boost:    FP.agentTransferFrom(user → booster, seasonId, amount)
Operator deposits:    FP.agentTransferFrom(operator → booster, seasonId, amount)
User claims reward:   FP.agentTransferFrom(booster → user, seasonId, payout)
Purge unclaimed:      FP.agentTransferFrom(booster → recipient, seasonId, totalSweep)
```

---

## TypeScript Tools

Located in `tools/booster/`:

| Tool | Description |
|------|-------------|
| `create-event.ts` | Create a new event with fights |
| `check-event-fights.ts` | View event details and fight statuses |
| `check-roles.ts` | Verify role assignments |
| `grant-operator-role.ts` | Grant OPERATOR_ROLE |
| `set-min-boost-amount.ts` | Configure minimum boost |
| `set-event-boost-cutoff.ts` | Set cutoff for all fights in event |
| `set-fight-boost-cutoff.ts` | Set cutoff for specific fight |
| `deposit-bonus.ts` | Deposit bonus FP to fight |
| `submit-fight-result.ts` | Submit fight results |
| `cancel-fight.ts` | Cancel a fight |
| `set-event-claim-ready.ts` | Enable/disable claims |
| `view-event.ts` | Detailed event info |
| `view-fight-stakes.ts` | View stakes and predictions |
| `view-quote-claimable.ts` | Check claimable amounts |

**Common usage:**
```bash
ts-node tools/booster/create-event.ts \
  --network testnet \
  --eventId UFC_300 \
  --numFights 12 \
  --seasonId 324001 \
  --defaultBoostCutoff 1769896800
```

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Reentrancy | `nonReentrant` on all token-moving functions |
| Result manipulation | `claimReady` flag locks results before claims |
| Fund safety | `claimedAmount` tracking prevents double-claiming |
| Operator errors | Results updatable until `claimReady`; `cancelFight` for emergencies |
| Stuck funds | `purgeEvent` sweeps unclaimed after deadline |
| Integer overflow | Uses Solidity 0.8.x built-in overflow checks |
| Upgrade safety | Only `DEFAULT_ADMIN_ROLE`; 50-slot storage gap |
| Redundant writes | Short-circuit pattern on config setters |

**Trust assumption:** The operator is trusted to submit correct results and fair points. All result calculations (`sumWinnersStakes`, `winningPoolTotalShares`) are computed off-chain by the operator.

---

## Test Coverage

**Test files:**
- `test/Booster.t.sol` - Comprehensive unit tests (~1700+ lines)
- `test/BoosterFP.t.sol` - Integration test with FP1155

| Category | What's Tested |
|----------|--------------|
| Event creation | Validation, defaults, season checks |
| Boost placement | Amount validation, cutoff, status checks |
| Boost increase | addToBoost validation, ownership |
| Fight status | Forward-only transitions |
| Result submission | Points validation, winner/method consistency, batch |
| Reward claims | Winning boosts, losing boosts revert, multi-fight batch |
| Cancelled fights | Full refund, no-contest auto-cancel |
| Bonus deposits | Limits, force flag |
| Claim deadlines | Enforcement, purge after deadline |
| Quote functions | claimable, historical, cancelled |
| Configuration | Min boost, max fights, max bonus |
| Access control | Role checks on all functions |

```bash
forge test --match-contract Booster -vv
```

---

## FAQ

**Q: Can a user change their prediction after placing a boost?**
A: No. Users can only add more FP to an existing boost (`addToBoost`), but cannot change the predicted winner or method. To bet on a different outcome, place a new boost.

**Q: What happens if no one wins a fight?**
A: If `sumWinnersStakes == 0`, claims return 0 for that fight. Funds remain in the contract and can be purged after the deadline.

**Q: Can results be changed after submission?**
A: Yes, results can be resubmitted as long as `claimReady` is false. Once `setEventClaimReady(true)` is called, results are locked.

**Q: How does the claim deadline work?**
A: If set, users must claim before the deadline. After it passes, the operator can call `purgeEvent` to sweep all unclaimed FP.

**Q: What's the difference between `cancelFight` and submitting Corner.NONE?**
A: Both result in `cancelled=true` and full refunds. `cancelFight` is for explicit cancellation before resolution. Submitting `Corner.NONE` with `NO_CONTEST` is for post-fight no-contest rulings. Both paths lead to the same refund behavior.

**Q: Does the Booster hold FP tokens?**
A: Yes. The contract holds all staked FP and bonus deposits. Tokens are held until users claim or funds are purged.

**Q: What is `winningPoolTotalShares` exactly?**
A: It's the sum of `(points * stakeAmount)` for every winning boost across all winning users. This is computed off-chain by the operator and submitted with the result. It's the denominator in the payout formula.
