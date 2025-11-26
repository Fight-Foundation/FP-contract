/**
 * @notice Script to set season status (OPEN or LOCKED) in the FP1155 contract
 *
 * @example Open a season
 * ts-node tools/fp/set-season-status.ts --network testnet --seasonId 323 --status open
 *
 * @example Lock a season
 * ts-node tools/fp/set-season-status.ts --network testnet --seasonId 323 --status locked
 *
 * @example With custom contract address
 * ts-node tools/fp/set-season-status.ts --contract 0x123... --seasonId 323 --status open
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function setSeasonStatus(uint256 seasonId, uint8 status) external",
  "function seasonStatus(uint256 seasonId) external view returns (uint8)",
];

// SeasonStatus enum values
const SeasonStatus = {
  OPEN: 0,
  LOCKED: 1,
};

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

  const pk = process.env.SEASON_ADMIN_PK || process.env.ADMIN_PK || process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing SEASON_ADMIN_PK/ADMIN_PK/OPERATOR_PK/PRIVATE_KEY in .env");
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

  const seasonId = BigInt(args.seasonId ?? args.season ?? 0);
  if (seasonId < 0n) throw new Error("--seasonId (or --season) must be >= 0");

  const statusStr = (args.status || "").toLowerCase();
  let status: number;
  if (statusStr === "open") {
    status = SeasonStatus.OPEN;
  } else if (statusStr === "locked") {
    status = SeasonStatus.LOCKED;
  } else {
    throw new Error('--status must be "open" or "locked"');
  }

  const fp1155 = new ethers.Contract(contract, ABI, wallet);

  // Check current status
  try {
    const currentStatus = await fp1155.seasonStatus(seasonId);
    const statusName = currentStatus === 0n ? "OPEN" : "LOCKED";
    console.log(`Current status for season ${seasonId}: ${statusName}`);
  } catch (err) {
    console.log(`Could not read current status (may be new season)`);
  }

  const statusName = status === SeasonStatus.OPEN ? "OPEN" : "LOCKED";
  console.log(`Setting season ${seasonId} to ${statusName}...`);

  const tx = await fp1155.setSeasonStatus(seasonId, status);
  console.log("Submitted setSeasonStatus tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify new status
  const newStatus = await fp1155.seasonStatus(seasonId);
  const newStatusName = newStatus === 0n ? "OPEN" : "LOCKED";
  console.log(`✓ Season ${seasonId} is now ${newStatusName}`);
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

