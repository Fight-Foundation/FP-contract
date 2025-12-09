/**
 * @notice Script to submit multiple fight results from a JSON file
 *
 * @example Submit all fight results from JSON file (uses resolutions.json in same folder by default)
 * ts-node tools/booster/batch-submit/submit-batch-results.ts --network testnet
 *
 * @example Submit with custom file path
 * ts-node tools/booster/batch-submit/submit-batch-results.ts \
 *   --network testnet \
 *   --file tools/booster/batch-submit/custom-resolutions.json
 *
 * Winner values: RED (0), BLUE (1), NONE (2)
 * Method values: KNOCKOUT/KO (0), SUBMISSION/SUB (1), DECISION/DEC (2), NO_CONTEST (3)
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";
import * as fs from "fs";
import * as path from "path";

// Corner enum: RED=0, BLUE=1, NONE=2
// WinMethod enum: KNOCKOUT=0, SUBMISSION=1, DECISION=2, NO_CONTEST=3
const ABI = [
  "function submitFightResult(string calldata eventId, uint256 fightId, uint8 winner, uint8 method, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 sumWinnersStakes, uint256 winningPoolTotalShares) external",
  "function submitFightResults(string calldata eventId, tuple(uint256 fightId, uint8 winner, uint8 method, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 sumWinnersStakes, uint256 winningPoolTotalShares)[] inputs) external",
  "function getFight(string calldata eventId, uint256 fightId) external view returns (uint8 status, uint8 winner, uint8 method, uint256 bonusPool, uint256 originalPool, uint256 sumWinnersStakes, uint256 winningPoolTotalShares, uint256 pointsForWinner, uint256 pointsForWinnerMethod, uint256 claimedAmount, uint256 boostCutoff, bool cancelled)",
];

// Network name to environment variable mapping
const NETWORK_ENV_MAP: Record<string, string> = {
  testnet: "TESTNET_BSC_RPC_URL",
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
  totalAmountStaked?: string; // Optional: used for validation against contract
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

  // Skip point and stake validations for NONE winner (NO_CONTEST)
  if (winner !== 2) {
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
}

// Validate totalAmountStaked against contract originalPool
async function validateTotalAmountStaked(
  booster: ethers.Contract,
  eventId: string,
  fight: FightResult
): Promise<void> {
  if (!fight.totalAmountStaked) {
    // If totalAmountStaked is not provided, skip validation
    return;
  }

  const expectedTotal = BigInt(fight.totalAmountStaked);
  const getFightFunc = booster.getFunction("getFight");
  const fightResult = (await getFightFunc(eventId, fight.fightId)) as unknown as any[];
  // getFight returns: status, winner, method, bonusPool, originalPool, sumWinnersStakes, ...
  const originalPool = fightResult[4]; // originalPool is at index 4

  if (BigInt(originalPool.toString()) !== expectedTotal) {
    throw new Error(
      `Fight ${fight.fightId}: totalAmountStaked mismatch! ` +
      `Expected: ${expectedTotal}, Contract originalPool: ${originalPool.toString()}`
    );
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

// Submit multiple fight results in a single transaction
async function submitBatchFightResults(
  booster: ethers.Contract,
  eventId: string,
  fights: FightResult[]
): Promise<{ hash: string; blockNumber: number }> {
  // Prepare inputs array
  const inputs = fights.map((fight) => ({
    fightId: BigInt(fight.fightId),
    winner: parseWinner(fight.winner),
    method: parseMethod(fight.method),
    pointsForWinner: BigInt(fight.pointsForWinner),
    pointsForWinnerMethod: BigInt(fight.pointsForWinnerMethod),
    sumWinnersStakes: BigInt(fight.sumWinnersStakes),
    winningPoolTotalShares: BigInt(fight.winningPoolTotalShares),
  }));
  
  // Print inputs exactly as they will be sent to the contract
  console.log("\n" + "=".repeat(60));
  console.log("BATCH SUBMISSION INPUTS (exact contract values)");
  console.log("=".repeat(60));
  for (let i = 0; i < inputs.length; i++) {
    const input = inputs[i];
    console.log(`\nIndex ${i} (fightId: ${input.fightId.toString()}):`);
    console.log(`  fightId:              ${input.fightId.toString()} (uint256)`);
    console.log(`  winner:               ${input.winner} (uint8) - ${getWinnerName(input.winner)}`);
    console.log(`  method:               ${input.method} (uint8) - ${getMethodName(input.method)}`);
    console.log(`  pointsForWinner:      ${input.pointsForWinner.toString()} (uint256)`);
    console.log(`  pointsForWinnerMethod: ${input.pointsForWinnerMethod.toString()} (uint256)`);
    console.log(`  sumWinnersStakes:    ${input.sumWinnersStakes.toString()} (uint256)`);
    console.log(`  winningPoolTotalShares: ${input.winningPoolTotalShares.toString()} (uint256)`);
  }
  console.log("\n" + "=".repeat(60));
  console.log(`\nTotal fights to submit: ${inputs.length}`);
  console.log(`Event ID: ${eventId}`);
  
  const confirmed = await askConfirmation("\nDo you want to submit these inputs? (y/n): ");
  if (!confirmed) {
    console.log("Batch submission cancelled by user.");
    process.exit(0);
  }
  const tx = await booster.submitFightResults(eventId, inputs);
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

  // Use resolutions.json in the same folder as the script by default
  // Get the directory of the current script file
  const scriptDir = path.dirname(require.main?.filename || process.argv[1] || __dirname);
  const defaultFilePath = path.join(scriptDir, "resolutions.json");
  const filePath = args.file || defaultFilePath;

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
  console.log(`File:              ${filePath}`);
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

  // Validate totalAmountStaked against contract originalPool for each fight (only on mainnet)
  if (networkName !== "testnet") {
    console.log("=".repeat(60));
    console.log("VALIDATING TOTAL AMOUNT STAKED (vs originalPool)");
    console.log("=".repeat(60));
    const readOnlyBooster = new ethers.Contract(contract, ABI, provider);
    for (const fight of data.fights) {
      if (fight.totalAmountStaked) {
        try {
          await validateTotalAmountStaked(readOnlyBooster, data.eventId, fight);
          console.log(`✅ Fight ${fight.fightId}: totalAmountStaked matches contract originalPool (${fight.totalAmountStaked})`);
        } catch (err: any) {
          throw new Error(`Validation failed: ${err.message || err}`);
        }
      } else {
        console.log(`⚠️  Fight ${fight.fightId}: totalAmountStaked not provided, skipping validation`);
      }
    }
    console.log(`✅ All totalAmountStaked validations completed\n`);
  }

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

  if (confirmEach) {
    // Individual confirmation mode: submit one by one
    console.log("\n⏳ Starting individual submission...\n");
    const results: Array<{ fightId: number; success: boolean; hash?: string; error?: string }> = [];

    for (let i = 0; i < data.fights.length; i++) {
      const fight = data.fights[i];
      console.log(`\n[${i + 1}/${data.fights.length}] Processing Fight ${fight.fightId}...`);

      // Validate totalAmountStaked before submitting (skip on testnet)
      if (fight.totalAmountStaked && networkName !== "testnet") {
        try {
          const readOnlyBooster = new ethers.Contract(contract, ABI, provider);
          await validateTotalAmountStaked(readOnlyBooster, data.eventId, fight);
          console.log(`  ✅ totalAmountStaked validated: ${fight.totalAmountStaked}`);
        } catch (err: any) {
          console.log(`  ❌ Validation error: ${err.message || err}`);
          results.push({ fightId: fight.fightId, success: false, error: `Validation failed: ${err.message || err}` });
          continue;
        }
      }

      const winner = parseWinner(fight.winner);
      const method = parseMethod(fight.method);
      console.log(`  Winner:            ${getWinnerName(winner)} (${winner})`);
      console.log(`  Method:            ${getMethodName(method)} (${method})`);
      console.log(`  Points (Winner):   ${fight.pointsForWinner}`);
      console.log(`  Points (Winner+Method): ${fight.pointsForWinnerMethod}`);
      console.log(`  Sum Winners Stakes: ${fight.sumWinnersStakes}`);
      console.log(`  Winning Pool Shares: ${fight.winningPoolTotalShares}`);
      const confirmed = await askConfirmation("  Submit this fight? (y/n): ");
      if (!confirmed) {
        console.log("  ⏭️  Skipped by user");
        results.push({ fightId: fight.fightId, success: false, error: "Skipped by user" });
        continue;
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

    // Summary for individual mode
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
  } else {
    // Batch mode: submit all fights in a single transaction
    console.log("\n⏳ Submitting all fights in a single transaction...\n");
    try {
      const result = await submitBatchFightResults(booster, data.eventId, data.fights);
      console.log(`✅ Transaction sent: ${result.hash}`);
      console.log(`✅ Confirmed in block: ${result.blockNumber}`);
      console.log(`✅ All ${data.fights.length} fights submitted successfully in one transaction\n`);
    } catch (err: any) {
      console.error(`❌ Error submitting batch: ${err.message || err}`);
      throw err;
    }
  }
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

