/**
 * @notice Script to view event information from the Booster contract
 *
 * @example Using testnet
 * ts-node tools/booster/view-event.ts --network testnet --eventId ufc-323
 *
 * @example Using mainnet
 * ts-node tools/booster/view-event.ts --network mainnet --eventId UFC_300
 *
 * @example With custom contract address
 * ts-node tools/booster/view-event.ts --contract 0x123... --eventId ufc-323
 *
 * @example View specific fight details
 * ts-node tools/booster/view-event.ts --network testnet --eventId ufc-323 --fightId 1
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/view-event.ts --network testnet --event ufc-323 --fight 1
 */
import "dotenv/config";
import { ethers } from "ethers";
import {
  parseArgs,
  setupBoosterConfig,
} from "./booster.utils";

// Enum values from Booster contract
enum FightStatus {
  OPEN = 0,
  CLOSED = 1,
  RESOLVED = 2,
}

enum Corner {
  RED = 0,
  BLUE = 1,
  NONE = 2,
}

enum WinMethod {
  KNOCKOUT = 0,
  SUBMISSION = 1,
  DECISION = 2,
  NO_CONTEST = 3,
}

const ABI = [
  "function getEvent(string calldata eventId) external view returns (uint256 seasonId, uint256 numFights, bool exists, bool claimReady)",
  "function getEventClaimDeadline(string calldata eventId) external view returns (uint256)",
  "function isEventClaimReady(string calldata eventId) external view returns (bool)",
  "function getEventFights(string calldata eventId) external view returns (uint256[] memory fightIds, uint8[] memory statuses)",
  "function getFight(string calldata eventId, uint256 fightId) external view returns (uint8 status, uint8 winner, uint8 method, uint256 bonusPool, uint256 originalPool, uint256 sumWinnersStakes, uint256 winningPoolTotalShares, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 claimedAmount, uint256 boostCutoff, bool cancelled)",
  "function totalPool(string calldata eventId, uint256 fightId) external view returns (uint256)",
];

// Helper to convert enum values from contract (uint8) to numbers
function toNumber(value: any): number {
  return typeof value === "bigint" ? Number(value) : value;
}

function formatStatus(status: number): string {
  switch (status) {
    case FightStatus.OPEN:
      return "OPEN";
    case FightStatus.CLOSED:
      return "CLOSED";
    case FightStatus.RESOLVED:
      return "RESOLVED";
    default:
      return `UNKNOWN(${status})`;
  }
}

function formatCorner(corner: number): string {
  switch (corner) {
    case Corner.RED:
      return "RED";
    case Corner.BLUE:
      return "BLUE";
    case Corner.NONE:
      return "NONE";
    default:
      return `UNKNOWN(${corner})`;
  }
}

function formatWinMethod(method: number): string {
  switch (method) {
    case WinMethod.KNOCKOUT:
      return "KNOCKOUT";
    case WinMethod.SUBMISSION:
      return "SUBMISSION";
    case WinMethod.DECISION:
      return "DECISION";
    case WinMethod.NO_CONTEST:
      return "NO_CONTEST";
    default:
      return `UNKNOWN(${method})`;
  }
}

function formatTimestamp(timestamp: bigint): string {
  if (timestamp === 0n) {
    return "Not set";
  }
  const date = new Date(Number(timestamp) * 1000);
  return `${timestamp.toString()} (${date.toISOString()})`;
}

function formatEther(wei: bigint): string {
  return `${wei.toString()} FP`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = await setupBoosterConfig(args);

  // Log network mode for clarity
  console.log(`Network mode: ${config.networkMode.toUpperCase()}`);
  console.log(`Contract: ${config.contractAddress}\n`);

  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error("Missing --eventId (or --event)");

  const booster = new ethers.Contract(config.contractAddress, ABI, config.provider);

  try {
    // Get event information (use getFunction to avoid conflict with getEvent for logs)
    const getEventFunc = booster.getFunction("getEvent");
    const eventResult = (await getEventFunc(eventId)) as unknown as any[];
    const seasonId = eventResult[0];
    const numFights = eventResult[1];
    const exists = eventResult[2];
    const claimReady = eventResult[3];

    if (!exists) {
      console.error(`❌ Event "${eventId}" does not exist`);
      process.exit(1);
    }

    console.log("📋 Event Information:");
    console.log(`  Event ID: ${eventId}`);
    console.log(`  Season ID: ${seasonId.toString()}`);
    console.log(`  Number of fights: ${numFights.toString()}`);
    console.log(`  Claim Ready: ${claimReady ? "✅ Yes" : "❌ No"}`);

    // Get claim deadline
    const getEventClaimDeadlineFunc = booster.getFunction("getEventClaimDeadline");
    const claimDeadline = await getEventClaimDeadlineFunc(eventId);
    console.log(`  Claim Deadline: ${formatTimestamp(claimDeadline)}`);

    // Get all fights statuses
    const getEventFightsFunc = booster.getFunction("getEventFights");
    const fightsResult = (await getEventFightsFunc(eventId)) as unknown as any[];
    const fightIds = fightsResult[0];
    const statuses = fightsResult[1];
    console.log(`\n🥊 Fights Status (${fightIds.length} total):`);
    
    // Get cutoff for first fight to check if all have the same (common case)
    const getFightFunc = booster.getFunction("getFight");
    const firstFightResult = (await getFightFunc(eventId, fightIds[0])) as unknown as any[];
    const firstFightCutoff = firstFightResult[10]; // boostCutoff is at index 10
    
    // Show status and cutoff for each fight
    for (let i = 0; i < fightIds.length; i++) {
      const status = formatStatus(toNumber(statuses[i]));
      // Get cutoff for this fight
      const fightResult = (await getFightFunc(eventId, fightIds[i])) as unknown as any[];
      const cutoff = fightResult[10];
      
      let cutoffStr = "";
      if (cutoff && BigInt(cutoff.toString()) > 0n) {
        cutoffStr = ` | Cutoff: ${formatTimestamp(BigInt(cutoff.toString()))}`;
      } else {
        cutoffStr = " | Cutoff: Not set";
      }
      
      console.log(`  Fight ${fightIds[i]}: ${status}${cutoffStr}`);
    }

    // If specific fight requested, show detailed information
    const fightIdArg = args.fightId || args.fight;
    if (fightIdArg) {
      const fightId = BigInt(fightIdArg);
      if (fightId <= 0n || fightId > numFights) {
        throw new Error(`Invalid fightId: ${fightId}. Must be between 1 and ${numFights}`);
      }

      console.log(`\n🔍 Detailed Fight Information (Fight ${fightId}):`);
      const getFightFunc = booster.getFunction("getFight");
      const fightResult = (await getFightFunc(eventId, fightId)) as unknown as any[];
      const status = fightResult[0];
      const winner = fightResult[1];
      const method = fightResult[2];
      const bonusPool = fightResult[3];
      const originalPool = fightResult[4];
      const sumWinnersStakes = fightResult[5];
      const winningPoolTotalShares = fightResult[6];
      const pointsForWinner = fightResult[7];
      const pointsForWinnerMethod = fightResult[8];
      const claimedAmount = fightResult[9];
      const boostCutoff = fightResult[10];
      const cancelled = fightResult[11];

      const statusNum = toNumber(status);
      console.log(`  Status: ${formatStatus(statusNum)}`);
      console.log(`  Boost Cutoff: ${formatTimestamp(boostCutoff)}`);
      console.log(`  Cancelled: ${cancelled ? "Yes" : "No"}`);

      if (statusNum === FightStatus.RESOLVED) {
        console.log(`  Winner: ${formatCorner(toNumber(winner))}`);
        console.log(`  Method: ${formatWinMethod(toNumber(method))}`);
        console.log(`  Points for Winner: ${pointsForWinner.toString()}`);
        console.log(`  Points for Winner+Method: ${pointsForWinnerMethod.toString()}`);
        console.log(`  Sum Winners Stakes: ${formatEther(sumWinnersStakes)}`);
        console.log(`  Winning Pool Total Shares: ${winningPoolTotalShares.toString()}`);
      }

      console.log(`  Original Pool (user stakes): ${formatEther(originalPool)}`);
      console.log(`  Bonus Pool: ${formatEther(bonusPool)}`);
      
      const totalPoolFunc = booster.getFunction("totalPool");
      const totalPoolAmount = await totalPoolFunc(eventId, fightId);
      console.log(`  Total Pool: ${formatEther(totalPoolAmount)}`);
      
      console.log(`  Claimed Amount: ${formatEther(claimedAmount)}`);
      
      const unclaimed = BigInt(totalPoolAmount.toString()) - BigInt(claimedAmount.toString());
      console.log(`  Unclaimed: ${formatEther(unclaimed)}`);
    }

    console.log("\n✅ Query completed successfully");
  } catch (error: any) {
    console.error("\n❌ Error querying event information:");
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

