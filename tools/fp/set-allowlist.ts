/**
 * @notice Script to add/remove addresses from FP1155 transfer allowlist
 *
 * @example Add address to allowlist
 * ts-node tools/fp/set-allowlist.ts --network testnet --address 0xf362fe668d93c43be16716a73702333795fbcea6 --allowed true
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function setTransferAllowlist(address account, bool allowed) external",
  "function isOnAllowlist(address account) external view returns (bool)",
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

  const address = args.address || args.to;
  if (!address) throw new Error("Missing --address (or --to)");
  if (!ethers.isAddress(address)) throw new Error("Invalid address format");

  const allowedStr = args.allowed || args.allow;
  if (!allowedStr) throw new Error("Missing --allowed (true/false)");
  const allowed = allowedStr.toLowerCase() === "true" || allowedStr === "1";

  const fp1155 = new ethers.Contract(contract, ABI, wallet);

  // Check current status
  const currentStatus = await fp1155.isOnAllowlist(address);
  console.log(`Current allowlist status for ${address}: ${currentStatus}`);
  
  if (currentStatus === allowed) {
    console.log(`✓ Address is already ${allowed ? "allowed" : "not allowed"}`);
    return;
  }

  console.log(`Setting allowlist for ${address} to ${allowed}...`);
  const tx = await fp1155.setTransferAllowlist(address, allowed);
  console.log("Submitted setTransferAllowlist tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify
  const newStatus = await fp1155.isOnAllowlist(address);
  console.log(`✓ Allowlist status updated: ${newStatus}`);
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












