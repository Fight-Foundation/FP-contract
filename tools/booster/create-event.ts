/**
 * @notice Script to create a new event with multiple fights in the Booster contract
 * 
 * @example
 * ts-node tools/booster/create-event.ts --eventId 322 --numFights 10 --seasonId 322
 * 
 * @example With custom contract address
 * ts-node tools/booster/create-event.ts --contract 0x123... --eventId 322 --numFights 10 --seasonId 322
 * 
 * @example Using alternative parameter names
 * ts-node tools/booster/create-event.ts --event 322 --fights 10 --season 322
 */
import 'dotenv/config';
import { ethers } from 'ethers';

const ABI = [
  'function createEvent(string calldata eventId, uint256 numFights, uint256 seasonId) external',
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

  const numFights = BigInt(args.numFights ?? args.fights ?? 0);
  if (numFights <= 0n) throw new Error('--numFights (or --fights) must be > 0');

  const seasonId = BigInt(args.seasonId ?? args.season ?? 0);
  if (seasonId <= 0n) throw new Error('--seasonId (or --season) must be > 0');

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log(`Creating event: ${eventId}, numFights: ${numFights}, seasonId: ${seasonId}`);
  const tx = await booster.createEvent(eventId, numFights, seasonId);
  console.log('Submitted createEvent tx:', tx.hash);
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

