# How to Play - Booster Contract

This guide describes how to use the Booster contract from creating events to claiming rewards.

## 📋 Prerequisites

1. Configure environment variables in `.env`:
   ```env
   TESTNET_BSC_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545/
   TESTNET_BOOSTER_ADDRESS=0x...
   TESTNET_FP1155_ADDRESS=0x...
   
   # Private keys
   PRIVATE_KEY_USER=0x...          # User who places boosts and claims
   PRIVATE_KEY_OPERATOR=0x...       # Operator who manages events
   ```

2. Have FP tokens minted for user and operator as needed.

## 🔄 Complete Testing Flow

### Step 1: Create an Event

The operator creates a new event with a number of fights and a season ID.

```bash
npm run create-event -- <eventId> <numFights> <seasonId> <boostCutoff>
```

**Example:**
```bash
npm run create-event -- ufc-323 2 323 1765062000
```

**Parameters:**
- `eventId`: Unique event identifier (e.g: `ufc-323`)
- `numFights`: Number of fights in the event (e.g: `2`)
- `seasonId`: FP token season ID (e.g: `323`)
- `boostCutoff`: Boost cutoff timestamp (e.g: `1765062000`)

---

### Step 2: Verify the Event

Verify that the event was created correctly:

```bash
npm run get-event -- <eventId>
```

**Example:**
```bash
npm run get-event -- ufc-323
```

This will show:
- Season ID
- Number of fights
- If it exists
- If it's in "claim ready" state

---

### Step 3: Place Boosts (Bet)

Users place boosts on fights. Each boost requires:
- Fight ID
- Amount of FP tokens
- Winner prediction (0=RED, 1=BLUE)
- Victory method (0=KNOCKOUT, 1=SUBMISSION, 2=DECISION)

```bash
npm run place-boost -- <userPk|operatorPk> <eventId> <fightId> <amount> <winner> <method>
```

**Example - User places boost on Fight 1:**
```bash
npm run place-boost -- userPk ufc-323 1 1000000 0 0
```

**Parameters:**
- `userPk` or `operatorPk`: Uses `PRIVATE_KEY_USER` or `PRIVATE_KEY_OPERATOR` respectively
- `eventId`: Event ID
- `fightId`: Fight ID (1, 2, 3, ...)
- `amount`: Amount of FP tokens to bet
- `winner`: 0=RED, 1=BLUE
- `method`: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION

**Example - Multiple boosts:**
```bash
# User bets on Fight 1: RED + KNOCKOUT
npm run place-boost -- userPk ufc-323 1 1000000 0 0

# User bets on Fight 2: BLUE + SUBMISSION
npm run place-boost -- userPk ufc-323 2 25 1 1
```

**Note:** The script automatically checks balance before placing the boost.

---

### Step 4: Submit Fight Results

The operator submits fight results. This resolves the fight and calculates winners.

```bash
npm run submit-result -- <eventId> <fightId> <winner> <method> <pointsWinner> <pointsWinnerMethod> <sumWinnersStakes> <winningPoolTotalShares>
```

**Example - Fight 1: RED wins by KNOCKOUT:**
```bash
npm run submit-result -- ufc-323 1 0 0 3 4 1000000 20000
```

**Parameters:**
- `eventId`: Event ID
- `fightId`: Fight ID
- `winner`: 0=RED, 1=BLUE, 2=NONE
- `method`: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION, 3=NO_CONTEST
- `pointsWinner`: Points for correct winner only
- `pointsWinnerMethod`: Points for correct winner + method
- `sumWinnersStakes`: Sum of stakes from all winners
- `winningPoolTotalShares`: Total shares of winning pool (points * amount from each winning boost)

**Example - Fight 2: BLUE wins by SUBMISSION:**
```bash
npm run submit-result -- ufc-323 2 1 1 3 4 25 500
```

**Note:** The values of `sumWinnersStakes` and `winningPoolTotalShares` must be calculated correctly:
- `sumWinnersStakes`: Sum of all `amount` from winning boosts
- `winningPoolTotalShares`: Sum of `points * amount` from all winning boosts

---

### Step 5: Mark Event as "Claim Ready"

After resolving all fights, the operator marks the event as ready to claim:

```bash
npm run set-claim-ready -- <eventId> <true|false>
```

**Example:**
```bash
npm run set-claim-ready -- ufc-323 true
```

This enables users to claim their rewards.

---

### Step 6: Check Claimable (After Resolving)

Now that fights are resolved, check how much you can claim:

```bash
npm run check-claimable -- <userPk|operatorPk> <eventId> [fightId]
```

**Example:**
```bash
npm run check-claimable -- userPk ufc-323
```

This will show:
- For each resolved fight
- Fight status (RESOLVED)
- Claimable amount in FP
- Total claimable

---

### Step 7: Claim Rewards

The user claims their rewards from winning boosts:

```bash
npm run claim -- <userPk|operatorPk> <eventId> [fightId]
```

**Example - Claim all fights:**
```bash
npm run claim -- userPk ufc-323
```

**Example - Claim only a specific fight:**
```bash
npm run claim -- userPk ufc-323 1
```

---

## 📝 Complete Example

Here's a complete example from start to finish:

```bash
# 1. Create event
npm run create-event -- ufc-323 2 323 1765062000

# 2. Verify event
npm run get-event -- ufc-323

# 3. User places boosts
npm run place-boost -- userPk ufc-323 1 1000000 0 0  # Fight 1: RED + KNOCKOUT
npm run place-boost -- userPk ufc-323 2 25 1 1        # Fight 2: BLUE + SUBMISSION

# 4. Operator resolves fights
npm run submit-result -- ufc-323 1 0 0 3 4 1000000 20000  # Fight 1: RED + KNOCKOUT
npm run submit-result -- ufc-323 2 1 1 3 4 25 500          # Fight 2: BLUE + SUBMISSION

# 5. Mark as claim ready
npm run set-claim-ready -- ufc-323 true

# 6. Check claimable (now will show amounts)
npm run check-claimable -- userPk ufc-323

# 7. User claims
npm run claim -- userPk ufc-323
```

---

## 🔍 Available Scripts

| Script | Description | Usage |
|--------|-------------|-----|
| `create-event` | Create a new event | `npm run create-event -- <eventId> <numFights> <seasonId> <boostCutoff>` |
| `get-event` | View event information | `npm run get-event -- <eventId>` |
| `place-boost` | Place a boost (bet) | `npm run place-boost -- <userPk\|operatorPk> <eventId> <fightId> <amount> <winner> <method>` |
| `check-claimable` | Check how much can be claimed | `npm run check-claimable -- <userPk\|operatorPk> <eventId> [fightId]` |
| `submit-result` | Submit fight result | `npm run submit-result -- <eventId> <fightId> <winner> <method> <pointsWinner> <pointsWinnerMethod> <sumWinnersStakes> <winningPoolTotalShares>` |
| `set-claim-ready` | Mark event as ready to claim | `npm run set-claim-ready -- <eventId> <true\|false>` |
| `claim` | Claim rewards | `npm run claim -- <userPk\|operatorPk> <eventId> [fightId]` |

---

## ⚠️ Important Notes

1. **FP Token Balance**: Make sure you have enough FP tokens before placing boosts. The `place-boost` script automatically checks balance.

2. **Result Calculation**: When submitting results, the values of `sumWinnersStakes` and `winningPoolTotalShares` must be calculated correctly:
   - `sumWinnersStakes`: Sum of all `amount` from winning boosts
   - `winningPoolTotalShares`: Sum of `points * amount` from all winning boosts

3. **Claim Ready**: Users can only claim after the event is marked as "claim ready".

4. **Boost Indices**: The `claim` script automatically gets all user boost indices using `getUserBoostIndices`. You don't need to specify them manually.

5. **Automatic Filtering**: The contract automatically filters valid boosts (belong to user, not claimed, and are winners).

6. **Amount Display**: Claimable amounts are shown as whole numbers (indivisible FP), not as decimals.

---

## 🐛 Troubleshooting

### Error: "not boost owner"
- Make sure to use the correct private key (`userPk` for user, `operatorPk` for operator)
- Verify that boosts belong to the address making the claim

### Error: "event not claim ready"
- The event must be marked as "claim ready" before claiming
- Use `npm run set-claim-ready -- <eventId> true`

### Error: "insufficient balance"
- Make sure you have enough FP tokens before placing boosts
- Verify you're using the correct season ID

### Error: "fight not resolved"
- The fight must be resolved before you can claim
- Use `npm run submit-result` to resolve the fight

---

## 📚 References

- Booster Contract: `src/Booster.sol`
- Test scripts: `booster-playground/src/`
- Contract ABI: `booster-playground/src/booster-abi.json`
