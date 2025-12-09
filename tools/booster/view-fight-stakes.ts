/**
 * @notice Script to view total stakes (apuestas) for a specific fight
 *
 * @example Using testnet
 * ts-node tools/booster/view-fight-stakes.ts --network testnet --eventId ufc-323 --fightId 1
 *
 * @example Using mainnet
 * ts-node tools/booster/view-fight-stakes.ts --network mainnet --eventId UFC_300 --fightId 1
 *
 * @example With custom contract address
 * ts-node tools/booster/view-fight-stakes.ts --contract 0x123... --eventId ufc-323 --fightId 1
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/view-fight-stakes.ts --network testnet --event ufc-323 --fight 1
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function getFight(string calldata eventId, uint256 fightId) external view returns (uint8 status, uint8 winner, uint8 method, uint256 bonusPool, uint256 originalPool, uint256 sumWinnersStakes, uint256 winningPoolTotalShares, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 claimedAmount, uint256 boostCutoff, bool cancelled)",
  "function totalPool(string calldata eventId, uint256 fightId) external view returns (uint256)",
];

function parseArgs(argv: string[]) {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const value = argv[i + 1];
      if (value && !value.startsWith("--")) {
        out[key] = value;
        i++;
      } else {
        out[key] = "true";
      }
    }
  }
  return out;
}

function formatEther(wei: bigint): string {
  return `${wei.toString()} FP`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const networkName = (args.network || args.net || "").toLowerCase();

  // Determine RPC URL based on network parameter
  let rpcUrl: string | undefined = args.rpc;
  if (!rpcUrl) {
    if (networkName === "mainnet") {
      rpcUrl = process.env.MAINNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else if (networkName === "testnet") {
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else {
      // Default to testnet if network not specified
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    }
  }

  if (!rpcUrl) {
    const envVar =
      networkName === "mainnet"
        ? "MAINNET_BSC_RPC_URL"
        : networkName === "testnet"
          ? "TESTNET_BSC_RPC_URL"
          : "TESTNET_BSC_RPC_URL or RPC_URL";
    throw new Error(`Missing RPC URL (set --rpc or ${envVar} in .env)`);
  }
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // Get contract address
  const contract =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
      : networkName === "mainnet"
        ? process.env.MAINNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
        : process.env.BOOSTER_ADDRESS);

  if (!contract) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_BOOSTER_ADDRESS"
        : networkName === "mainnet"
          ? "MAINNET_BOOSTER_ADDRESS"
          : "BOOSTER_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error("Missing --eventId (or --event)");

  const fightId = BigInt(args.fightId ?? args.fight ?? 0);
  if (fightId <= 0n) throw new Error("--fightId (or --fight) must be > 0");

  // Get network information
  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);

  // Determine actual network based on chainId
  let actualNetwork: string;
  if (chainId === 56) {
    actualNetwork = "BSC Mainnet";
  } else if (chainId === 97) {
    actualNetwork = "BSC Testnet";
  } else {
    actualNetwork = network.name || `Chain ID ${chainId}`;
  }

  console.log(`Network: ${actualNetwork}`);
  console.log(`Contract: ${contract}\n`);

  const booster = new ethers.Contract(contract, ABI, provider);

  try {
    // Get fight information
    const getFightFunc = booster.getFunction("getFight");
    const fightResult = (await getFightFunc(eventId, fightId)) as unknown as any[];
    const status = fightResult[0];
    const bonusPool = fightResult[3];
    const originalPool = fightResult[4];
    const claimedAmount = fightResult[9];

    // Get total pool
    const totalPoolFunc = booster.getFunction("totalPool");
    const totalPoolAmount = await totalPoolFunc(eventId, fightId);

    console.log("📊 Fight Stakes Information:");
    console.log("─".repeat(60));
    console.log(`Event ID: ${eventId}`);
    console.log(`Fight ID: ${fightId.toString()}`);
    console.log(`\n💰 Stakes Breakdown:`);
    console.log(`  Total User Stakes (originalPool): ${formatEther(originalPool)}`);
    console.log(`  Bonus Pool: ${formatEther(bonusPool)}`);
    console.log(`  Total Pool (stakes + bonus): ${formatEther(totalPoolAmount)}`);
    console.log(`  Claimed Amount: ${formatEther(claimedAmount)}`);

    const unclaimed = BigInt(totalPoolAmount.toString()) - BigInt(claimedAmount.toString());
    console.log(`  Unclaimed: ${formatEther(unclaimed)}`);

    console.log("\n✅ Query completed successfully");
  } catch (error: any) {
    console.error("\n❌ Error querying fight stakes:");
    if (error.reason) {
      console.error(`  Reason: ${error.reason}`);
    }
    if (error.message) {
      console.error(`  Message: ${error.message}`);
    }
    throw error;
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

