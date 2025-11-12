import 'dotenv/config';
import { ethers } from 'ethers';

const ABI = [
  'function setFightBoostCutoff(string calldata eventId, uint256 fightId, uint256 cutoff) external',
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

  const cutoff = args.cutoff || args.timestamp;
  if (!cutoff) throw new Error('Missing --cutoff (or --timestamp)');
  const cutoffBigInt = BigInt(cutoff);

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log(`Setting boost cutoff for event: ${eventId}, fightId: ${fightId}, cutoff: ${cutoffBigInt}`);
  const tx = await booster.setFightBoostCutoff(eventId, fightId, cutoffBigInt);
  console.log('Submitted setFightBoostCutoff tx:', tx.hash);
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

