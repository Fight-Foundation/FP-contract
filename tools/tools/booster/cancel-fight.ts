/**
 * @notice Script to cancel a fight (no-contest scenario - enables full refunds)
 *
 * @example Cancel a single fight
 * ts-node tools/booster/cancel-fight.ts --network mainnet --eventId ufc-323 --fightId 1
 * ts-node tools/booster/cancel-fight.ts --network mainnet --eventId ufc-fight-night-dec-13-2025 --fightId 2
 *
 * @example Cancel multiple fights (comma-separated)
 * ts-node tools/booster/cancel-fight.ts --network mainnet --eventId ufc-323 --fightIds 1,2,3
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/cancel-fight.ts --network testnet --event ufc-323 --fight 1
 *
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";

const ABI = [
  "function cancelFight(string calldata eventId, uint256 fightId) external",
  "function getFight(string calldata eventId, uint256 fightId) external view returns (uint8 status, uint8 winner, uint8 method, uint256 bonusPool, uint256 originalPool, uint256 sumWinnersStakes, uint256 winningPoolTotalShares, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 claimedAmount, uint256 boostCutoff, bool cancelled)",
];

// Network name to environment variable mapping
const NETWORK_ENV_MAP: Record<string, string> = {
  testnet: "TESTNET_BSC_RPC_URL",
  mainnet: "MAINNET_BSC_RPC_URL",
};

// Fight status enum
enum FightStatus {
  OPEN = 0,
  CLOSED = 1,
  RESOLVED = 2,
}

function getStatusName(status: number): string {
  const statuses = ["OPEN", "CLOSED", "RESOLVED"];
  return statuses[status] || `UNKNOWN (${status})`;
}

function getRpcUrl(args: Record<string, string>): string {
  const networkName = args.network || args.net;
  if (!networkName) {
    throw new Error("Missing --network (required: testnet or mainnet)");
  }

  const envVar = NETWORK_ENV_MAP[networkName.toLowerCase()];
  if (!envVar) {
    throw new Error(
      `Unknown network "${networkName}". Supported: ${Object.keys(
        NETWORK_ENV_MAP
      ).join(", ")}`
    );
  }

  const url = process.env[envVar];
  if (!url) {
    throw new Error(
      `Network "${networkName}" requires ${envVar} to be set in .env`
    );
  }

  return url;
}

// Function to ask for user confirmation
function askConfirmation(question: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === "y" || normalized === "yes");
    });
  });
}

async function getFightInfo(
  booster: ethers.Contract,
  eventId: string,
  fightId: bigint
): Promise<{
  status: number;
  winner: number;
  method: number;
  bonusPool: bigint;
  originalPool: bigint;
  cancelled: boolean;
}> {
  const getFightFunc = booster.getFunction("getFight");
  const result = (await getFightFunc(eventId, fightId)) as unknown as any[];
  return {
    status: Number(result[0]),
    winner: Number(result[1]),
    method: Number(result[2]),
    bonusPool: BigInt(result[3].toString()),
    originalPool: BigInt(result[4].toString()),
    cancelled: result[11],
  };
}

async function cancelFight(
  booster: ethers.Contract,
  eventId: string,
  fightId: bigint
): Promise<{ hash: string; blockNumber: number }> {
  const tx = await booster.cancelFight(eventId, fightId);
  const rcpt = await tx.wait();
  return { hash: tx.hash, blockNumber: rcpt.blockNumber };
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

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = getRpcUrl(args);
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing OPERATOR_PK (or PRIVATE_KEY) in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const networkName = (args.network || args.net || "").toLowerCase();
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

  // Parse fight IDs - support both single fightId and comma-separated fightIds
  const fightIdStr = args.fightId || args.fight || args.fightIds;
  if (!fightIdStr) {
    throw new Error("Missing --fightId (or --fight or --fightIds)");
  }

  const fightIds = fightIdStr
    .split(",")
    .map((id) => id.trim())
    .map((id) => BigInt(id))
    .filter((id) => id > 0n);

  if (fightIds.length === 0) {
    throw new Error("No valid fight IDs provided");
  }

  const booster = new ethers.Contract(contract, ABI, wallet);
  const readOnlyBooster = new ethers.Contract(contract, ABI, provider);

  // Display fight information before cancellation
  console.log("\n" + "=".repeat(60));
  console.log("FIGHT CANCELLATION REVIEW");
  console.log("=".repeat(60));
  console.log(`Network:           ${networkName}`);
  console.log(`Contract Address:  ${contract}`);
  console.log(`Wallet Address:    ${wallet.address}`);
  console.log(`Event ID:          ${eventId}`);
  console.log(`Fights to cancel:  ${fightIds.length}`);
  console.log("=".repeat(60));
  console.log("\nFIGHT INFORMATION:");
  console.log("-".repeat(60));

  const fightInfos: Array<{
    fightId: bigint;
    status: number;
    originalPool: bigint;
    cancelled: boolean;
  }> = [];

  for (const fightId of fightIds) {
    try {
      const info = await getFightInfo(readOnlyBooster, eventId, fightId);
      fightInfos.push({
        fightId,
        status: info.status,
        originalPool: info.originalPool,
        cancelled: info.cancelled,
      });

      console.log(`\nFight ${fightId.toString()}:`);
      console.log(`  Status:           ${getStatusName(info.status)} (${info.status})`);
      console.log(`  Original Pool:    ${info.originalPool.toString()} FP`);
      console.log(`  Bonus Pool:       ${info.bonusPool.toString()} FP`);
      console.log(`  Already Cancelled: ${info.cancelled ? "YES" : "NO"}`);

      if (info.status === FightStatus.RESOLVED && !info.cancelled) {
        console.log(`  ⚠️  WARNING: Fight is already RESOLVED and not cancelled!`);
      }
    } catch (err: any) {
      throw new Error(`Failed to get fight info for fightId ${fightId}: ${err.message || err}`);
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("\n⚠️  WARNING: Cancelling a fight will:");
  console.log("  - Set status to RESOLVED");
  console.log("  - Set cancelled flag to true");
  console.log("  - Set winner to NONE");
  console.log("  - Set method to NO_CONTEST");
  console.log("  - Enable full refunds of principal for all users");
  console.log("=".repeat(60));

  // Show exact parameters that will be sent to the contract
  console.log("\n" + "=".repeat(60));
  console.log("CANCELLATION INPUTS (exact contract values)");
  console.log("=".repeat(60));
  for (let i = 0; i < fightIds.length; i++) {
    const fightId = fightIds[i];
    const fightInfo = fightInfos[i];
    
    if (fightInfo.cancelled) {
      console.log(`\nFight ${i + 1} (fightId: ${fightId.toString()}):`);
      console.log(`  ⚠️  Already cancelled - will be skipped`);
      continue;
    }
    
    if (fightInfo.status === FightStatus.RESOLVED) {
      console.log(`\nFight ${i + 1} (fightId: ${fightId.toString()}):`);
      console.log(`  ⚠️  Already resolved - will be skipped`);
      continue;
    }
    
    console.log(`\nFight ${i + 1} (fightId: ${fightId.toString()}):`);
    console.log(`  eventId:            "${eventId}" (string)`);
    console.log(`  fightId:             ${fightId.toString()} (uint256)`);
  }
  console.log("\n" + "=".repeat(60));
  console.log(`\nTotal fights to cancel: ${fightIds.length}`);
  console.log(`Event ID: ${eventId}`);

  // Ask for confirmation
  const confirmed = await askConfirmation(
    `\nDo you want to cancel these fights? (y/n): `
  );

  if (!confirmed) {
    console.log("\n❌ Cancellation cancelled by user.");
    process.exit(0);
  }

  // Cancel fights
  console.log("\n⏳ Cancelling fights...\n");
  const results: Array<{
    fightId: bigint;
    success: boolean;
    hash?: string;
    blockNumber?: number;
    error?: string;
  }> = [];

  for (let i = 0; i < fightIds.length; i++) {
    const fightId = fightIds[i];
    const fightInfo = fightInfos[i];

    // Check if already cancelled
    if (fightInfo.cancelled) {
      console.log(`⚠️  Fight ${fightId.toString()}: Already cancelled, skipping...`);
      results.push({
        fightId,
        success: false,
        error: "Already cancelled",
      });
      continue;
    }

    // Check if already resolved (but not cancelled)
    if (fightInfo.status === FightStatus.RESOLVED) {
      console.log(`⚠️  Fight ${fightId.toString()}: Already resolved, cannot cancel`);
      results.push({
        fightId,
        success: false,
        error: "Already resolved",
      });
      continue;
    }

    try {
      console.log(`[${i + 1}/${fightIds.length}] Cancelling Fight ${fightId.toString()}...`);
      const result = await cancelFight(booster, eventId, fightId);
      console.log(`  ✅ Transaction sent: ${result.hash}`);
      console.log(`  ✅ Confirmed in block: ${result.blockNumber}`);
      results.push({
        fightId,
        success: true,
        hash: result.hash,
        blockNumber: result.blockNumber,
      });

      // Small delay between transactions to avoid nonce issues
      if (i < fightIds.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    } catch (err: any) {
      console.log(`  ❌ Error: ${err.message || err}`);
      results.push({
        fightId,
        success: false,
        error: err.message || String(err),
      });
    }
  }

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("CANCELLATION SUMMARY");
  console.log("=".repeat(60));
  const successful = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;
  console.log(`Total:     ${results.length}`);
  console.log(`Success:   ${successful}`);
  console.log(`Failed:    ${failed}`);

  if (failed > 0) {
    console.log("\nFailed fights:");
    for (const result of results) {
      if (!result.success) {
        console.log(`  Fight ${result.fightId.toString()}: ${result.error}`);
      }
    }
  }

  if (successful > 0) {
    console.log("\nSuccessful cancellations:");
    for (const result of results) {
      if (result.success) {
        console.log(`  Fight ${result.fightId.toString()}: ${result.hash}`);
      }
    }
  }

  console.log("=".repeat(60) + "\n");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

