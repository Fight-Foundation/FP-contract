/**
 * @notice Script to set the boost cutoff timestamp for all fights in an event (after which new boosts are rejected)
 * 
 * This function sets the cutoff for ALL fights in the event at once. Only fights that are not resolved will be updated.
 * 
 * How to calculate Unix timestamp:
 * - Current timestamp in terminal (Mac/Linux): date +%s
 * - Specific date in terminal (Mac): date -j -f "%Y-%m-%d %H:%M:%S" "2024-01-01 00:00:00" +%s
 * - Specific date in terminal (Linux): date -d "2024-01-01 00:00:00" +%s

 * @example Calculate timestamp for Nov 15, 2025 4:00 PM UTC-7 (using Node.js - recommended)
 * node -e "console.log(Math.floor(new Date('2025-11-15T16:00:00-07:00').getTime() / 1000))"
 * Note: This correctly converts 4:00 PM UTC-7 to 11:00 PM UTC (23:00:00 UTC)

 * 
 * @example Disable cutoff (set to 0, relies on status only)
 * ts-node tools/booster/set-event-boost-cutoff.ts --eventId UFC_300 --cutoff 0
 * 
 * @example Using alternative parameter names
 * ts-node tools/booster/set-event-boost-cutoff.ts --event UFC_300 --timestamp 1704067200
 * 
 * @example With custom contract address
 * ts-node tools/booster/set-event-boost-cutoff.ts --contract 0x123... --eventId UFC_300 --cutoff 1704067200
 */
import 'dotenv/config';
import { ethers } from 'ethers';

const ABI = [
  'function setEventBoostCutoff(string calldata eventId, uint256 cutoff) external',
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

  const cutoff = args.cutoff || args.timestamp;
  if (cutoff === undefined) throw new Error('Missing --cutoff (or --timestamp)');
  const cutoffBigInt = BigInt(cutoff);

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log(`Setting boost cutoff for all fights in event: ${eventId}, cutoff: ${cutoffBigInt}`);
  console.log('Note: Only fights that are not resolved will be updated.');
  const tx = await booster.setEventBoostCutoff(eventId, cutoffBigInt);
  console.log('Submitted setEventBoostCutoff tx:', tx.hash);
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

