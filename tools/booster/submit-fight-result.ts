/**
 * @notice Script to submit fight result with calculated points and shares
 * 
 * @example Submit result: RED corner wins by KNOCKOUT
 * ts-node tools/booster/submit-fight-result.ts \
 *   --eventId UFC_300 \
 *   --fightId 1 \
 *   --winner RED \
 *   --method KNOCKOUT \
 *   --pointsForWinner 10 \
 *   --pointsForWinnerMethod 20 \
 *   --sumWinnersStakes 10000000000000000000 \
 *   --winningPoolTotalShares 200000000000000000000
 * 
 * @example Submit result: BLUE corner wins by DECISION
 * ts-node tools/booster/submit-fight-result.ts \
 *   --eventId UFC_300 \
 *   --fightId 2 \
 *   --winner BLUE \
 *   --method DECISION \
 *   --pointsForWinner 10 \
 *   --pointsForWinnerMethod 15 \
 *   --sumWinnersStakes 5000000000000000000 \
 *   --winningPoolTotalShares 75000000000000000000
 * 
 * @example Using numeric values for winner and method
 * ts-node tools/booster/submit-fight-result.ts \
 *   --eventId UFC_300 \
 *   --fightId 1 \
 *   --winner 0 \
 *   --method 0 \
 *   --pointsForWinner 10 \
 *   --pointsForWinnerMethod 20 \
 *   --sumWinnersStakes 10000000000000000000 \
 *   --winningPoolTotalShares 200000000000000000000
 * 
 * @example Using alternative parameter names
 * ts-node tools/booster/submit-fight-result.ts \
 *   --event UFC_300 \
 *   --fight 1 \
 *   --winner RED \
 *   --method KO \
 *   --pointsWinner 10 \
 *   --pointsMethod 20 \
 *   --sumStakes 10000000000000000000 \
 *   --totalShares 200000000000000000000
 * 
 * Winner values: RED (0), BLUE (1), NONE (2)
 * Method values: KNOCKOUT/KO (0), SUBMISSION/SUB (1), DECISION/DEC (2), NO_CONTEST (3)
 */
import 'dotenv/config';
import { ethers } from 'ethers';

// Corner enum: RED=0, BLUE=1, NONE=2
// WinMethod enum: KNOCKOUT=0, SUBMISSION=1, DECISION=2, NO_CONTEST=3
const ABI = [
  'function submitFightResult(string calldata eventId, uint256 fightId, uint8 winner, uint8 method, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 sumWinnersStakes, uint256 winningPoolTotalShares) external',
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.RPC_URL || process.env.BSC_TESTNET_RPC_URL || process.env.BSC_RPC_URL;
  if (!rpcUrl) throw new Error('Missing RPC URL (set --rpc or RPC_URL/BSC_TESTNET_RPC_URL/BSC_RPC_URL)');
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error('Missing OPERATOR_PK (or PRIVATE_KEY) in .env');
  const wallet = new ethers.Wallet(pk.startsWith('0x') ? pk : ('0x' + pk), provider);

  const contract = args.contract || process.env.BOOSTER_ADDRESS;
  if (!contract) throw new Error('Missing contract (set --contract or BOOSTER_ADDRESS)');

  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error('Missing --eventId (or --event)');

  const fightId = BigInt(args.fightId ?? args.fight ?? 0);
  if (fightId <= 0n) throw new Error('--fightId (or --fight) must be > 0');

  // Parse winner: RED=0, BLUE=1, NONE=2
  const winnerStr = (args.winner || '').toUpperCase();
  let winner: number;
  if (winnerStr === 'RED' || winnerStr === '0') winner = 0;
  else if (winnerStr === 'BLUE' || winnerStr === '1') winner = 1;
  else if (winnerStr === 'NONE' || winnerStr === '2') winner = 2;
  else throw new Error('--winner must be RED (0), BLUE (1), or NONE (2)');

  // Parse method: KNOCKOUT=0, SUBMISSION=1, DECISION=2, NO_CONTEST=3
  const methodStr = (args.method || '').toUpperCase();
  let method: number;
  if (methodStr === 'KNOCKOUT' || methodStr === 'KO' || methodStr === '0') method = 0;
  else if (methodStr === 'SUBMISSION' || methodStr === 'SUB' || methodStr === '1') method = 1;
  else if (methodStr === 'DECISION' || methodStr === 'DEC' || methodStr === '2') method = 2;
  else if (methodStr === 'NO_CONTEST' || methodStr === '3') method = 3;
  else throw new Error('--method must be KNOCKOUT (0), SUBMISSION (1), DECISION (2), or NO_CONTEST (3)');

  const pointsForWinner = BigInt(args.pointsForWinner ?? args.pointsWinner ?? 0);
  if (pointsForWinner <= 0n) throw new Error('--pointsForWinner (or --pointsWinner) must be > 0');

  const pointsForWinnerMethod = BigInt(args.pointsForWinnerMethod ?? args.pointsMethod ?? 0);
  if (pointsForWinnerMethod < pointsForWinner) {
    throw new Error('--pointsForWinnerMethod (or --pointsMethod) must be >= pointsForWinner');
  }

  const sumWinnersStakes = BigInt(args.sumWinnersStakes ?? args.sumStakes ?? 0);
  if (sumWinnersStakes < 0n) throw new Error('--sumWinnersStakes (or --sumStakes) must be >= 0');

  const winningPoolTotalShares = BigInt(args.winningPoolTotalShares ?? args.totalShares ?? 0);
  if (winningPoolTotalShares <= 0n) throw new Error('--winningPoolTotalShares (or --totalShares) must be > 0');

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log(`Submitting fight result:`);
  console.log(`  Event: ${eventId}`);
  console.log(`  FightId: ${fightId}`);
  console.log(`  Winner: ${winner} (${winnerStr})`);
  console.log(`  Method: ${method} (${methodStr})`);
  console.log(`  Points for winner: ${pointsForWinner}`);
  console.log(`  Points for winner+method: ${pointsForWinnerMethod}`);
  console.log(`  Sum winners stakes: ${sumWinnersStakes}`);
  console.log(`  Winning pool total shares: ${winningPoolTotalShares}`);
  
  const tx = await booster.submitFightResult(
    eventId,
    fightId,
    winner,
    method,
    pointsForWinner,
    pointsForWinnerMethod,
    sumWinnersStakes,
    winningPoolTotalShares
  );
  console.log('Submitted submitFightResult tx:', tx.hash);
  const rcpt = await tx.wait();
  console.log('Mined in block', rcpt.blockNumber);
}

function parseArgs(argv: string[]) {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const val = argv[i + 1];
      out[key] = val;
      i++;
    }
  }
  return out;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

