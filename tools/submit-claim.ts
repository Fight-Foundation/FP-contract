import 'dotenv/config';
import { ethers } from 'ethers';

const ABI = [
  'function claim(uint256 seasonId,uint256 amount,uint256 deadline,bytes signature) external',
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.RPC_URL || process.env.TESTNET_BSC_RPC_URL || process.env.BSC_RPC_URL;
  if (!rpcUrl) throw new Error('Missing RPC URL (set --rpc or RPC_URL/TESTNET_BSC_RPC_URL/BSC_RPC_URL)');
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.USER_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error('Missing USER_PK (or PRIVATE_KEY) in .env');
  const wallet = new ethers.Wallet(pk.startsWith('0x') ? pk : ('0x' + pk), provider);

  const contract = args.contract || process.env.FP1155_ADDRESS;
  if (!contract) throw new Error('Missing contract (set --contract or FP1155_ADDRESS)');

  const seasonId = BigInt(args.season ?? 0);
  const amount = BigInt(args.amount ?? 0);
  const deadline = BigInt(args.deadline ?? 0);
  const signature = args.sig || args.signature;
  if (seasonId <= 0n) throw new Error('--season must be > 0');
  if (amount <= 0n) throw new Error('--amount must be > 0');
  if (deadline <= 0n) throw new Error('--deadline must be > 0');
  if (!signature) throw new Error('--sig (or --signature) is required');

  const fp = new ethers.Contract(contract, ABI, wallet);
  const tx = await fp.claim(seasonId, amount, deadline, signature);
  console.log('Submitted claim tx:', tx.hash);
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
