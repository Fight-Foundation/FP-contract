/**
 * @notice Script to submit multiple fight results from a JSON file
 *
 * @example Submit all fight results from JSON file
 * ts-node tools/booster/batch-submit/submit-batch-results.ts \
 *   --network testnet \
 *   --file tools/booster/batch-submit/fight-results-template.json
 *
 * Winner values: RED (0), BLUE (1), NONE (2)
 * Method values: KNOCKOUT/KO (0), SUBMISSION/SUB (1), DECISION/DEC (2), NO_CONTEST (3)
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";
import * as fs from "fs";

// Corner enum: RED=0, BLUE=1, NONE=2
// WinMethod enum: KNOCKOUT=0, SUBMISSION=1, DECISION=2, NO_CONTEST=3
const ABI = [
  "function submitFightResult(string calldata eventId, uint256 fightId, uint8 winner, uint8 method, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 sumWinnersStakes, uint256 winningPoolTotalShares) external",
];

// Network name to environment variable mapping
const NETWORK_ENV_MAP: Record<string, string> = {
  testnet: "BSC_TESTNET_RPC_URL",
  mainnet: "MAINNET_BSC_RPC_URL",
};

// Interface for fight result data
interface FightResult {
  fightId: number;
  winner: string;
  method: string;
  pointsForWinner: string;
  pointsForWinnerMethod: string;
  sumWinnersStakes: string;
  winningPoolTotalShares: string;
}

interface FightResultsFile {
  eventId: string;
  fights: FightResult[];
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

// Helper function to format method name
function getMethodName(method: number): string {
  const methods = ["KNOCKOUT", "SUBMISSION", "DECISION", "NO_CONTEST"];
  return methods[method] || `UNKNOWN (${method})`;
}

// Helper function to format winner name
function getWinnerName(winner: number): string {
  const winners = ["RED", "BLUE", "NONE"];
  return winners[winner] || `UNKNOWN (${winner})`;
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

// Parse winner string to number
function parseWinner(winnerStr: string): number {
  const normalized = winnerStr.toUpperCase();
  if (normalized === "RED" || normalized === "0") return 0;
  if (normalized === "BLUE" || normalized === "1") return 1;
  if (normalized === "NONE" || normalized === "2") return 2;
  throw new Error(`Invalid winner: ${winnerStr}. Must be RED (0), BLUE (1), or NONE (2)`);
}

// Parse method string to number
function parseMethod(methodStr: string): number {
  const normalized = methodStr.toUpperCase();
  if (normalized === "KNOCKOUT" || normalized === "KO" || normalized === "0") return 0;
  if (normalized === "SUBMISSION" || normalized === "SUB" || normalized === "1") return 1;
  if (normalized === "DECISION" || normalized === "DEC" || normalized === "2") return 2;
  if (normalized === "NO_CONTEST" || normalized === "3") return 3;
  throw new Error(
    `Invalid method: ${methodStr}. Must be KNOCKOUT (0), SUBMISSION (1), DECISION (2), or NO_CONTEST (3)`
  );
}

// Validate fight result data
function validateFightResult(fight: FightResult, eventId: string): void {
  if (!fight.fightId || fight.fightId <= 0) {
    throw new Error(`Fight ${fight.fightId}: fightId must be > 0`);
  }

  const winner = parseWinner(fight.winner);
  const method = parseMethod(fight.method);

  // Validate winner/method consistency
  if (winner === 2 && method !== 3) {
    throw new Error(`Fight ${fight.fightId}: NONE winner requires NO_CONTEST method`);
  }

  const pointsForWinner = BigInt(fight.pointsForWinner);
  if (pointsForWinner <= 0n) {
    throw new Error(`Fight ${fight.fightId}: pointsForWinner must be > 0`);
  }

  const pointsForWinnerMethod = BigInt(fight.pointsForWinnerMethod);
  if (pointsForWinnerMethod < pointsForWinner) {
    throw new Error(
      `Fight ${fight.fightId}: pointsForWinnerMethod must be >= pointsForWinner`
    );
  }

  const sumWinnersStakes = BigInt(fight.sumWinnersStakes);
  if (sumWinnersStakes < 0n) {
    throw new Error(`Fight ${fight.fightId}: sumWinnersStakes must be >= 0`);
  }

  const winningPoolTotalShares = BigInt(fight.winningPoolTotalShares);
  if (winningPoolTotalShares <= 0n) {
    throw new Error(`Fight ${fight.fightId}: winningPoolTotalShares must be > 0`);
  }
}

// Submit a single fight result
async function submitSingleFightResult(
  booster: ethers.Contract,
  eventId: string,
  fight: FightResult
): Promise<{ hash: string; blockNumber: number }> {
  const winner = parseWinner(fight.winner);
  const method = parseMethod(fight.method);
  const pointsForWinner = BigInt(fight.pointsForWinner);
  const pointsForWinnerMethod = BigInt(fight.pointsForWinnerMethod);
  const sumWinnersStakes = BigInt(fight.sumWinnersStakes);
  const winningPoolTotalShares = BigInt(fight.winningPoolTotalShares);

  const tx = await booster.submitFightResult(
    eventId,
    fight.fightId,
    winner,
    method,
    pointsForWinner,
    pointsForWinnerMethod,
    sumWinnersStakes,
    winningPoolTotalShares
  );

  const rcpt = await tx.wait();
  return { hash: tx.hash, blockNumber: rcpt.blockNumber };
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

  const filePath = args.file;
  if (!filePath) {
    throw new Error("Missing --file parameter (path to JSON file with fight results)");
  }

  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }

  const fileContent = fs.readFileSync(filePath, "utf-8");
  let data: FightResultsFile;
  try {
    data = JSON.parse(fileContent);
  } catch (err) {
    throw new Error(`Invalid JSON file: ${err}`);
  }

  if (!data.eventId) {
    throw new Error("Missing eventId in JSON file");
  }

  if (!data.fights || !Array.isArray(data.fights) || data.fights.length === 0) {
    throw new Error("Missing or empty fights array in JSON file");
  }

  const booster = new ethers.Contract(contract, ABI, wallet);

  // Validate all fights before proceeding
  console.log("\n" + "=".repeat(60));
  console.log("VALIDATING FIGHT RESULTS");
  console.log("=".repeat(60));
  for (const fight of data.fights) {
    try {
      validateFightResult(fight, data.eventId);
    } catch (err) {
      throw new Error(`Validation failed: ${err}`);
    }
  }
  console.log(`✅ All ${data.fights.length} fights validated successfully\n`);

  // Display comprehensive review
  console.log("=".repeat(60));
  console.log("BATCH SUBMISSION REVIEW");
  console.log("=".repeat(60));
  console.log(`Network:           ${args.network || args.net}`);
  console.log(`Contract Address:  ${contract}`);
  console.log(`Wallet Address:    ${wallet.address}`);
  console.log(`Event ID:          ${data.eventId}`);
  console.log(`Total Fights:      ${data.fights.length}`);
  console.log("=".repeat(60));
  console.log("\nFIGHT RESULTS:");
  console.log("-".repeat(60));

  for (const fight of data.fights) {
    const winner = parseWinner(fight.winner);
    const method = parseMethod(fight.method);
    console.log(`\nFight ${fight.fightId}:`);
    console.log(`  Winner:            ${getWinnerName(winner)} (${winner})`);
    console.log(`  Method:            ${getMethodName(method)} (${method})`);
    console.log(`  Points (Winner):   ${fight.pointsForWinner}`);
    console.log(`  Points (Winner+Method): ${fight.pointsForWinnerMethod}`);
    console.log(`  Sum Winners Stakes: ${fight.sumWinnersStakes}`);
    console.log(`  Winning Pool Shares: ${fight.winningPoolTotalShares}`);
  }

  console.log("\n" + "=".repeat(60));
  console.log("");

  // Ask for confirmation
  const confirmed = await askConfirmation(
    `Do you want to submit all ${data.fights.length} fight results? (y/n): `
  );

  if (!confirmed) {
    console.log("\n❌ Batch submission cancelled by user.");
    process.exit(0);
  }

  // Ask for confirmation mode
  const confirmEach = await askConfirmation(
    "Do you want to confirm each fight individually? (y/n): "
  );

  console.log("\n⏳ Starting batch submission...\n");

  const results: Array<{ fightId: number; success: boolean; hash?: string; error?: string }> = [];

  for (let i = 0; i < data.fights.length; i++) {
    const fight = data.fights[i];
    console.log(`\n[${i + 1}/${data.fights.length}] Processing Fight ${fight.fightId}...`);

    if (confirmEach) {
      const winner = parseWinner(fight.winner);
      const method = parseMethod(fight.method);
      console.log(`  Winner: ${getWinnerName(winner)}, Method: ${getMethodName(method)}`);
      const confirmed = await askConfirmation("  Submit this fight? (y/n): ");
      if (!confirmed) {
        console.log("  ⏭️  Skipped by user");
        results.push({ fightId: fight.fightId, success: false, error: "Skipped by user" });
        continue;
      }
    }

    try {
      const result = await submitSingleFightResult(booster, data.eventId, fight);
      console.log(`  ✅ Transaction sent: ${result.hash}`);
      console.log(`  ✅ Confirmed in block: ${result.blockNumber}`);
      results.push({ fightId: fight.fightId, success: true, hash: result.hash });
    } catch (err: any) {
      console.log(`  ❌ Error: ${err.message || err}`);
      results.push({ fightId: fight.fightId, success: false, error: err.message || String(err) });
    }

    // Small delay between transactions to avoid nonce issues
    if (i < data.fights.length - 1) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("BATCH SUBMISSION SUMMARY");
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
        console.log(`  Fight ${result.fightId}: ${result.error}`);
      }
    }
  }

  console.log("=".repeat(60) + "\n");
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

