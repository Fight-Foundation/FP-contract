# Booster Playground

Portable project to interact directly with the Booster contract on testnet. Includes embedded ABI and TypeScript client ready to use.

## Requirements

1. Node.js installed
2. `.env` file in the **root of the main project** (not in booster-playground) with:
   ```bash
   PRIVATE_KEY=0x...your_private_key
   TESTNET_BOOSTER_ADDRESS=0xdcA538E7385dc39888f8934D7D3e9E6beE2E8DEf
   TESTNET_BSC_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545/
   ```

**Note:** The `.env` must be in the root of the main project because the client looks for environment variables from there.

## Installation

```bash
cd booster-playground
npm install
```

Or from the project root:
```bash
npm install --prefix booster-playground
```

## Usage

### Method 1: Use npm scripts (Simplest)

```bash
# Create event
npm run create-event -- ufc-324 10 323 1765062000

# Deposit bonus
npm run deposit-bonus -- ufc-323 1 1000000

# Submit result
npm run submit-result -- ufc-323 1 0 0 3 4 5000000 10000000

# Set event cutoff
npm run set-cutoff -- event ufc-323 1765062000

# Set fight cutoff
npm run set-cutoff -- fight ufc-323 1 1765062000

# Read event information
npm run get-event -- ufc-323

# Place a boost
# Option 1: On behalf of user (pass their private key)
npm run place-boost -- userPk ufc-323 1 1000000 0 0

# Option 2: On behalf of operator (uses PRIVATE_KEY from .env)
npm run place-boost -- operatorPk ufc-323 1 1000000 0 0

# Check claimable
npm run check-claimable -- userPk ufc-323

# Claim rewards
npm run claim -- userPk ufc-323

# Set claim ready
npm run set-claim-ready -- ufc-323 true
```

### Method 2: Use contract directly (For custom scripts)

The project includes a TypeScript client with embedded ABI. You can import it and use the contract directly:

```typescript
import { getBooster } from './src/booster-client';

// Get contract instance
const booster = await getBooster();

// Create an event
const tx = await booster.createEvent('ufc-324', 10, 323, 1765062000);
await tx.wait();

// Deposit bonus
await booster.depositBonus('ufc-323', 1, 1000000, false);

// Read information (read-only, doesn't require wallet)
import { getBoosterReadOnly } from './src/booster-client';
const boosterRead = getBoosterReadOnly();
const [seasonId, numFights, exists, claimReady] = await boosterRead.getEvent('ufc-323');
```

## Project Structure

```
booster-playground/
├── src/
│   ├── booster-abi.json      # Complete Booster contract ABI
│   ├── booster-client.ts     # Client to connect to contract
│   ├── claim.ts              # Claim rewards script
│   ├── place-boost.ts        # Place boost script
│   ├── check-claimable.ts   # Check claimable script
│   ├── create-event.ts       # Create event script
│   ├── submit-result.ts      # Submit result script
│   └── ...                   # Other scripts
├── package.json
├── tsconfig.json
├── README.md
└── COMPLETE_GUIDE.md         # Complete testing guide
```

## Client API

### `getBooster()`: Get contract with wallet (for transactions)
```typescript
const booster = await getBooster();
// Can execute transactions that require OPERATOR_ROLE
```

### `getBoosterReadOnly()`: Get contract without wallet (read-only)
```typescript
const booster = getBoosterReadOnly();
// Only for reading data, doesn't require wallet or permissions
```

## Main Available Functions

- `createEvent(eventId, numFights, seasonId, defaultBoostCutoff)`
- `depositBonus(eventId, fightId, amount, force)`
- `submitFightResult(eventId, fightId, winner, method, pointsForWinner, pointsForWinnerMethod, sumWinnersStakes, winningPoolTotalShares)`
- `setEventBoostCutoff(eventId, cutoff)`
- `setFightBoostCutoff(eventId, fightId, cutoff)`
- `setMinBoostAmount(amount)`
- `getEvent(eventId)` - returns `[seasonId, numFights, exists, claimReady]`
- `getFight(eventId, fightId)` - returns complete fight information
- And more... see `booster-abi.json` for all functions

## Notes

- **Portable**: The project includes embedded ABI, doesn't depend on external files
- **Testnet only**: Specifically configured for BSC Testnet
- Amounts are in wei (no decimals, 1M = 1000000)
- Winner values: 0=RED, 1=BLUE, 2=NONE
- Method values: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION, 3=NO_CONTEST
- Status values: 0=OPEN, 1=CLOSED, 2=RESOLVED

## How to Play

For a complete step-by-step guide on how to use the Booster contract, see [HOW_TO_PLAY.md](./HOW_TO_PLAY.md).
