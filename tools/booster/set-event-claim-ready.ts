/**
 * @notice Script to set the claim ready status for an event
 * 
 * This function allows operators to mark an event as ready (or not ready) for claims.
 * This provides flexibility in case of inconsistent results that need to be corrected before allowing claims.
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/set-event-claim-ready.ts --network testnet --event ufc-323 --ready true
 * ts-node tools/booster/set-event-claim-ready.ts --network mainnet --event ufc-323 --ready true
 * 
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";

const ABI = [
  "function setEventClaimReady(string calldata eventId, bool claimReady) external",
  "function getEvent(string calldata eventId) external view returns (uint256 seasonId, uint256 numFights, bool exists, bool claimReady)",
];

// Network name to environment variable mapping
const NETWORK_ENV_MAP: Record<string, string> = {
  testnet: "TESTNET_BSC_RPC_URL",
  mainnet: "MAINNET_BSC_RPC_URL",
};

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

  const claimReadyStr = args.claimReady || args.ready;
  if (claimReadyStr === undefined)
    throw new Error("Missing --claimReady (or --ready)");
  
  // Parse boolean value (accepts: true, false, 1, 0, yes, no)
  const claimReady = parseBoolean(claimReadyStr);

  const booster = new ethers.Contract(contract, ABI, wallet);
  const readOnlyBooster = new ethers.Contract(contract, ABI, provider);

  // Get current event information
  let currentClaimReady = false;
  try {
    const getEventFunc = readOnlyBooster.getFunction("getEvent");
    const eventResult = (await getEventFunc(eventId)) as unknown as any[];
    const exists = eventResult[2];
    currentClaimReady = eventResult[3];
    
    if (!exists) {
      console.error(`❌ Event "${eventId}" does not exist`);
      process.exit(1);
    }
  } catch (err: any) {
    console.warn(`⚠️  Could not fetch current event status: ${err.message || err}`);
  }

  // Display information before confirmation
  console.log("\n" + "=".repeat(60));
  console.log("SET EVENT CLAIM READY");
  console.log("=".repeat(60));
  console.log(`Network:           ${networkName}`);
  console.log(`Contract Address:  ${contract}`);
  console.log(`Wallet Address:    ${wallet.address}`);
  console.log(`Event ID:          ${eventId}`);
  console.log(`Current Status:    ${currentClaimReady ? "✅ Ready" : "❌ Not Ready"}`);
  console.log(`New Status:        ${claimReady ? "✅ Ready" : "❌ Not Ready"}`);
  console.log("=".repeat(60));

  if (currentClaimReady === claimReady) {
    console.log(`\n⚠️  Event "${eventId}" is already ${claimReady ? "ready" : "not ready"} for claims.`);
    console.log("No action needed.");
    process.exit(0);
  }

  // Show exact parameters that will be sent to the contract
  console.log("\n" + "=".repeat(60));
  console.log("TRANSACTION DETAILS");
  console.log("=".repeat(60));
  console.log(`Function:          setEventClaimReady`);
  console.log(`  eventId:          "${eventId}" (string)`);
  console.log(`  claimReady:       ${claimReady} (bool)`);
  console.log("=".repeat(60));

  // Ask for confirmation
  const confirmed = await askConfirmation(
    `\nDo you want to proceed with setting event "${eventId}" as ${claimReady ? "ready" : "not ready"} for claims? (y/n): `
  );

  if (!confirmed) {
    console.log("\n❌ Operation cancelled by user.");
    process.exit(0);
  }

  // Execute transaction
  console.log("\n⏳ Setting claim ready status...");
  const tx = await booster.setEventClaimReady(eventId, claimReady);
  console.log("Submitted setEventClaimReady tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);
  console.log(`\n✅ Event "${eventId}" is now ${claimReady ? "ready" : "not ready"} for claims`);
}

function parseBoolean(value: string): boolean {
  const lower = value.toLowerCase().trim();
  if (lower === "true" || lower === "1" || lower === "yes") return true;
  if (lower === "false" || lower === "0" || lower === "no") return false;
  throw new Error(`Invalid boolean value: ${value}. Use true/false, 1/0, or yes/no`);
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

