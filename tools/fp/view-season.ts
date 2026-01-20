/**
 * @notice Script to view season status in the FP1155 contract
 *
 * @example View season status
 * ts-node tools/fp/view-season.ts --network testnet --seasonId 323
 *
 * @example View multiple seasons
 * ts-node tools/fp/view-season.ts --network testnet --seasonId 323 --seasonId 322
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function seasonStatus(uint256 seasonId) external view returns (uint8)",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
  "function totalSupply(uint256 id) external view returns (uint256)",
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
    process.env.TESTNET_BSC_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or RPC_URL/TESTNET_BSC_RPC_URL/BSC_RPC_URL)"
    );
  const provider = new ethers.JsonRpcProvider(rpcUrl);

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

  // Get network information
  const network = await provider.getNetwork();
  const displayNetwork = networkName || network.name || `Chain ID ${network.chainId}`;

  // Parse season IDs (support multiple)
  const seasonIds: bigint[] = [];
  if (args.seasonId) {
    seasonIds.push(BigInt(args.seasonId));
  }
  if (args.season) {
    seasonIds.push(BigInt(args.season));
  }
  // Support multiple --seasonId arguments
  const allArgs = process.argv.slice(2);
  for (let i = 0; i < allArgs.length; i++) {
    if (allArgs[i] === "--seasonId" || allArgs[i] === "--season") {
      const val = allArgs[i + 1];
      if (val && !val.startsWith("--")) {
        const id = BigInt(val);
        if (!seasonIds.includes(id)) {
          seasonIds.push(id);
        }
      }
    }
  }

  if (seasonIds.length === 0) {
    throw new Error("Missing --seasonId (or --season). At least one season ID is required.");
  }

  const fp1155 = new ethers.Contract(contract, ABI, provider);

  console.log("Season Status Information");
  console.log("=".repeat(60));
  console.log(`Network: ${displayNetwork} (Chain ID: ${network.chainId})`);
  console.log(`Contract: ${contract}`);
  console.log();

  for (const seasonId of seasonIds) {
    try {
      const status = await fp1155.seasonStatus(seasonId);
      const statusValue = Number(status);
      const statusName = statusValue === SeasonStatus.OPEN ? "OPEN" : "LOCKED";
      const statusEmoji = statusValue === SeasonStatus.OPEN ? "🟢" : "🔴";

      console.log(`Season ${seasonId}:`);
      console.log("─".repeat(60));
      console.log(`Status: ${statusEmoji} ${statusName} (${statusValue})`);

      // Show what operations are allowed
      if (statusValue === SeasonStatus.OPEN) {
        console.log(`  ✓ Minting: Allowed`);
        console.log(`  ✓ Transfers: Allowed`);
        console.log(`  ✓ Claims: Allowed`);
        console.log(`  ✓ Burns: Allowed`);
      } else {
        console.log(`  ✗ Minting: Blocked`);
        console.log(`  ✗ Transfers: Blocked`);
        console.log(`  ✗ Claims: Blocked`);
        console.log(`  ✓ Burns: Allowed (always allowed)`);
      }

      // Try to get total supply if available (ERC1155 doesn't have totalSupply by default, but some implementations do)
      try {
        const totalSupply = await fp1155.totalSupply(seasonId);
        console.log(`Total Supply: ${totalSupply.toString()}`);
      } catch {
        // totalSupply might not be available, skip it
      }

      console.log();
    } catch (err: any) {
      console.log(`Season ${seasonId}:`);
      console.log("─".repeat(60));
      console.log(`Error: ${err.message || "Could not read season status"}`);
      console.log();
    }
  }
}

function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const val = argv[i + 1];
      if (val && !val.startsWith("--")) {
        out[key] = val;
        i++;
      } else {
        out[key] = "true";
      }
    }
  }
  return out;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});


