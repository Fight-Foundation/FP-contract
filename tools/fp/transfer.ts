/**
 * @notice Script to transfer FP tokens from one address to another
 *
 * @example Transfer 3M tokens from PRIVATE_KEY to another address
 * ts-node tools/fp/transfer.ts --network testnet --to 0xf362fe668d93c43be16716a73702333795fbcea6 --seasonId 323 --amount 3000000
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
  "function isOnAllowlist(address account) external view returns (bool)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl =
    args.rpc ||
    process.env.RPC_URL ||
    process.env.BSC_TESTNET_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or RPC_URL/BSC_TESTNET_RPC_URL/BSC_RPC_URL)"
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

  console.log(`Transferring ${amount} FP tokens (season ${seasonId})`);
  console.log(`From: ${wallet.address}`);
  console.log(`To: ${toAddress}`);
  console.log(`Contract: ${contract}\n`);

  // Check balance
  const balance = await fp1155.balanceOf(wallet.address, seasonId);
  console.log(`Current balance: ${balance.toString()}`);
  if (balance < amount) {
    throw new Error(`Insufficient balance: have ${balance.toString()}, need ${amount.toString()}`);
  }

  // Check allowlist status
  try {
    const fromAllowed = await fp1155.isOnAllowlist(wallet.address);
    const toAllowed = await fp1155.isOnAllowlist(toAddress);
    console.log(`From allowlist: ${fromAllowed}`);
    console.log(`To allowlist: ${toAllowed}`);
  } catch (err) {
    console.log("Could not check allowlist status");
  }

  console.log(`\nSending transaction...`);
  const tx = await fp1155.safeTransferFrom(
    wallet.address,
    toAddress,
    seasonId,
    amount,
    "0x"
  );
  console.log("Submitted transfer tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify new balances
  const newFromBalance = await fp1155.balanceOf(wallet.address, seasonId);
  const newToBalance = await fp1155.balanceOf(toAddress, seasonId);
  console.log(`\n✓ Transfer complete!`);
  console.log(`New balance (from): ${newFromBalance.toString()}`);
  console.log(`New balance (to): ${newToBalance.toString()}`);
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




