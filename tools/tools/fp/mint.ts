/**
 * @notice Script to mint FP tokens
 *
 * @example Mint 1M tokens to an address
 * ts-node tools/fp/mint.ts --network testnet --to 0xc312F7E46C0f14AE2931D922Af9484eD8868d12c --seasonId 323 --amount 1000000
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function mint(address to, uint256 seasonId, uint256 amount, bytes memory data) external",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl =
    args.rpc ||
    process.env.RPC_URL ||
    process.env.TESTNET_BSC_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or RPC_URL/TESTNET_BSC_RPC_URL/BSC_RPC_URL)"
    );
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing PRIVATE_KEY in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const networkName = (args.network || args.net || "").toLowerCase();
  const contract =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : process.env.FP1155_ADDRESS);
  if (!contract) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_FP1155_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_FP1155_ADDRESS"
        : "FP1155_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  const toAddress = args.to || args.address;
  if (!toAddress) throw new Error("Missing --to (or --address)");
  if (!ethers.isAddress(toAddress)) throw new Error("Invalid address format");

  const seasonId = BigInt(args.seasonId ?? args.season ?? 0);
  if (seasonId < 0n) throw new Error("--seasonId (or --season) must be >= 0");

  const amount = BigInt(args.amount ?? 0);
  if (amount <= 0n) throw new Error("--amount must be > 0");

  const fp1155 = new ethers.Contract(contract, ABI, wallet);

  console.log(`Minting ${amount} FP tokens (season ${seasonId})`);
  console.log(`To: ${toAddress}`);
  console.log(`Contract: ${contract}`);
  console.log(`From wallet: ${wallet.address}\n`);

  // Check current balance
  const balance = await fp1155.balanceOf(toAddress, seasonId);
  console.log(`Current balance: ${balance.toString()}`);

  console.log(`\nSending mint transaction...`);
  const tx = await fp1155.mint(toAddress, seasonId, amount, "0x");
  console.log("Submitted mint tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify new balance
  const newBalance = await fp1155.balanceOf(toAddress, seasonId);
  console.log(`\n✓ Mint complete!`);
  console.log(`New balance: ${newBalance.toString()}`);
}

function parseArgs(argv: string[]) {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
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

