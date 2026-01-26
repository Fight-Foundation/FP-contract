/**
 * @notice Script to create a new event with multiple fights in the Booster contract

 *
 * @example With network parameter
 * ts-node tools/booster/create-event.ts --network mainnet --eventId ufc-fight-night-dec-13-2025 --numFights 10 --seasonId 324001 --defaultBoostCutoff 1765666800
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";

const ABI = [
  "function createEvent(string calldata eventId, uint256 numFights, uint256 seasonId, uint256 defaultBoostCutoff) external",
];

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
    const envVar = networkName === "mainnet" 
      ? "MAINNET_BSC_RPC_URL" 
      : networkName === "testnet"
      ? "TESTNET_BSC_RPC_URL"
      : "TESTNET_BSC_RPC_URL or RPC_URL";
    throw new Error(
      `Missing RPC URL (set --rpc or ${envVar} in .env)`
    );
  }
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.OPERATOR_PK;
  if (!pk) throw new Error("Missing OPERATOR_PK in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );
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

  const numFights = BigInt(args.numFights ?? args.fights ?? 0);
  if (numFights <= 0n) throw new Error("--numFights (or --fights) must be > 0");

  const seasonId = BigInt(args.seasonId ?? args.season ?? 0);
  if (seasonId <= 0n) throw new Error("--seasonId (or --season) must be > 0");

  const defaultBoostCutoff = BigInt(args.defaultBoostCutoff ?? args.cutoff ?? 0);

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
  
  // Warn if network parameter doesn't match actual network
  if (networkName) {
    const expectedChainId = networkName === "mainnet" ? 56 : networkName === "testnet" ? 97 : null;
    if (expectedChainId !== null && chainId !== expectedChainId) {
      console.warn(`⚠️  Warning: --network ${networkName} specified but connected to Chain ID ${chainId} (${actualNetwork})`);
    }
  }

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log("Event Details:");
  console.log("─".repeat(60));
  console.log(`Event ID: ${eventId}`);
  console.log(`Number of Fights: ${numFights}`);
  console.log(`Season ID: ${seasonId}`);
  if (defaultBoostCutoff > 0n) {
    const cutoffDate = new Date(Number(defaultBoostCutoff) * 1000);
    console.log(`Default Boost Cutoff: ${defaultBoostCutoff.toString()} (${cutoffDate.toISOString()})`);
  } else {
    console.log(`Default Boost Cutoff: ${defaultBoostCutoff.toString()} (not set)`);
  }
  console.log();
  console.log("Transaction Details:");
  console.log("─".repeat(60));
  console.log(`Network: ${actualNetwork} (Chain ID: ${chainId})`);
  console.log(`Contract: ${contract}`);
  console.log(`From wallet: ${wallet.address}`);
  console.log();

  // Ask for confirmation
  const confirmed = await askConfirmation(
    "Do you want to proceed with creating this event? (yes/no): "
  );
  if (!confirmed) {
    console.log("Operation cancelled.");
    process.exit(0);
  }

  console.log("\nSending transaction...");
  const tx = await booster.createEvent(eventId, numFights, seasonId, defaultBoostCutoff);
  console.log("Submitted createEvent tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);
}

function askConfirmation(question: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === "yes" || normalized === "y");
    });
  });
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
