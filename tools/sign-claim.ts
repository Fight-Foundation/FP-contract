import 'dotenv/config';
import { ethers } from 'ethers';

const ABI = [
  'function nonces(address) view returns (uint256)'
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.RPC_URL || process.env.BSC_TESTNET_RPC_URL || process.env.BSC_RPC_URL;
  if (!rpcUrl) throw new Error('Missing RPC URL (set --rpc or RPC_URL/BSC_TESTNET_RPC_URL/BSC_RPC_URL)');
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.CLAIM_SIGNER_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error('Missing CLAIM_SIGNER_PK (or PRIVATE_KEY) in .env');
  const wallet = new ethers.Wallet(pk.startsWith('0x') ? pk : ('0x' + pk), provider);

  const contract = args.contract || process.env.FP1155_ADDRESS;
  if (!contract) throw new Error('Missing contract (set --contract or FP1155_ADDRESS)');

  const user = args.user;
  if (!user) throw new Error('Missing --user');

  const seasonId = BigInt(args.season ?? 0);
  const amount = BigInt(args.amount ?? 0);
  const deadline = BigInt(args.deadline ?? 0);
  if (seasonId <= 0n) throw new Error('--season must be > 0');
  if (amount <= 0n) throw new Error('--amount must be > 0');
  if (deadline <= 0n) throw new Error('--deadline must be > 0');

  const chainId = (await provider.getNetwork()).chainId;
  const fp = new ethers.Contract(contract, ABI, provider);
  const nonce = await fp.nonces(user);

  const domain = {
    name: 'FP1155',
    version: '1',
    chainId,
    verifyingContract: contract,
  } as const;

  const types = {
    Claim: [
      { name: 'account', type: 'address' },
      { name: 'seasonId', type: 'uint256' },
      { name: 'amount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  } as const;

  const message = {
    account: user,
    seasonId,
    amount,
    nonce,
    deadline,
  } as const;

  const signature = await wallet.signTypedData(domain as any, types as any, message as any);

  const out = {
    contract,
    chainId: chainId.toString(),
    account: user,
    seasonId: seasonId.toString(),
    amount: amount.toString(),
    nonce: nonce.toString(),
    deadline: deadline.toString(),
    signature,
  };
  console.log(JSON.stringify(out, null, 2));
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
