/**
 * @notice Script to check FP token (BEP-1155) balance for a wallet and season
 *
 * @example Check balance for a wallet with numeric seasonId
 * ts-node tools/fp/balance.ts --network mainnet --to 0x4a40e8d757d7fb82825fe6be75a7f6aee733290d --seasonId 323
 * ts-node tools/fp/balance.ts --network mainnet --to 0x91341dBC9f531fedCF790B7CAe85f997A8e1e9D4 --seasonId 323
 *
 * @example Check balance using eventId (string) to get seasonId from Booster
 * ts-node tools/fp/balance.ts --network mainnet --to 0x4a40e8d757d7fb82825fe6be75a7f6aee733290d --seasonId ufc-fight-night-nov-22-2025
 */
import "dotenv/config";
import { ethers } from "ethers";

const FP1155_ABI = [
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

const BOOSTER_ABI = [
  "function getEvent(string calldata eventId) external view returns (uint256 seasonId, uint256 numFights, bool exists, bool claimReady)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const networkName = (args.network || args.net || "").toLowerCase();
  
  // Select RPC URL based on network
  let rpcUrl: string | undefined = args.rpc;
  if (!rpcUrl) {
    if (networkName === "mainnet") {
      rpcUrl = process.env.BSC_RPC_URL || process.env.MAINNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else if (networkName === "testnet") {
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else {
      // Default fallback
      rpcUrl = process.env.RPC_URL || process.env.BSC_RPC_URL || process.env.TESTNET_BSC_RPC_URL || undefined;
    }
  }
  
  if (!rpcUrl) {
    const envVar = networkName === "mainnet" 
      ? "BSC_RPC_URL or MAINNET_BSC_RPC_URL"
      : networkName === "testnet"
      ? "TESTNET_BSC_RPC_URL"
      : "RPC_URL, BSC_RPC_URL, or TESTNET_BSC_RPC_URL";
    throw new Error(`Missing RPC URL for ${networkName || "default"} network (set --rpc or ${envVar} in .env)`);
  }
  
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const fp1155Address =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : process.env.FP1155_ADDRESS);
  if (!fp1155Address) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_FP1155_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_FP1155_ADDRESS"
        : "FP1155_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  const addressInput = args.to || args.address || args.wallet;
  if (!addressInput) throw new Error("Missing --to (or --address or --wallet)");
  if (!ethers.isAddress(addressInput)) throw new Error("Invalid address format");
  const address = ethers.getAddress(addressInput.trim().replace(/['"]/g, ""));

  const seasonIdInput = args.seasonId ?? args.season;
  if (!seasonIdInput) throw new Error("Missing --seasonId (or --season)");

  let seasonId: bigint;

  // Check if seasonId is a number or a string (eventId)
  const numericSeasonId = /^\d+$/.test(seasonIdInput);
  if (numericSeasonId) {
    // Direct numeric seasonId
    seasonId = BigInt(seasonIdInput);
    if (seasonId < 0n) throw new Error("--seasonId (or --season) must be >= 0");
  } else {
    // String eventId - get seasonId from Booster
    const boosterAddress =
      networkName === "testnet"
        ? process.env.TESTNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
        : networkName === "mainnet"
        ? process.env.MAINNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
        : process.env.BOOSTER_ADDRESS;
    if (!boosterAddress) {
      throw new Error(
        `Missing Booster address (set BOOSTER_ADDRESS or ${networkName === "testnet" ? "TESTNET_BOOSTER_ADDRESS" : networkName === "mainnet" ? "MAINNET_BOOSTER_ADDRESS" : "BOOSTER_ADDRESS"} in .env)`
      );
    }
    const booster = new ethers.Contract(
      ethers.getAddress(boosterAddress.trim().replace(/['"]/g, "")),
      BOOSTER_ABI,
      provider
    );
    const eventId = seasonIdInput;
    console.log(`Getting seasonId from eventId: ${eventId}`);
    const getEventFunc = booster.getFunction("getEvent");
    const [eventSeasonId, numFights, exists, claimReady] = await getEventFunc(
      eventId
    );
    if (!exists) {
      throw new Error(`Event "${eventId}" does not exist`);
    }
    seasonId = eventSeasonId;
    console.log(
      `Event found: seasonId=${seasonId.toString()}, numFights=${numFights.toString()}, claimReady=${claimReady}\n`
    );
  }

  const fp1155 = new ethers.Contract(
    ethers.getAddress(fp1155Address.trim().replace(/['"]/g, "")),
    FP1155_ABI,
    provider
  );

  console.log(`Checking FP token balance`);
  console.log(`Wallet: ${address}`);
  console.log(`Season ID: ${seasonId.toString()}`);
  console.log(`Contract: ${fp1155Address}\n`);

  // Normalize addresses
  const normalizedContract = ethers.getAddress(fp1155Address.trim().replace(/['"]/g, ""));
  const normalizedWallet = ethers.getAddress(address);
  
  // Get current block to ensure we're querying latest state
  const currentBlock = await provider.getBlockNumber();
  console.log(`Current block: ${currentBlock}`);
  console.log(`Normalized contract: ${normalizedContract}`);
  console.log(`Normalized wallet: ${normalizedWallet}`);
  console.log(`Season ID (BigInt): ${seasonId.toString()}\n`);

  try {
    console.log("Calling balanceOf via contract interface...");
    const balance = await fp1155.balanceOf(normalizedWallet, seasonId);
    console.log(`✓ Balance: ${balance.toString()} FP`);
  } catch (error: any) {
    console.error(`Contract method failed:`, error.message);
    console.log("\nTrying direct call method...");
    
    try {
      // Try direct call with encoded data
      const iface = new ethers.Interface(FP1155_ABI);
      const data = iface.encodeFunctionData("balanceOf", [normalizedWallet, seasonId]);
      
      console.log(`Encoded data: ${data}`);
      console.log(`Calling contract at ${normalizedContract}...`);
      
      const result = await provider.call({
        to: normalizedContract,
        data: data
      });
      
      console.log(`Raw result: ${result}`);
      
      // Decode the result
      const decoded = iface.decodeFunctionResult("balanceOf", result);
      const balance = decoded[0];
      
      console.log(`✓ Balance (direct call): ${balance.toString()} FP`);
    } catch (error2: any) {
      console.error(`Direct call also failed:`, error2.message);
      throw error;
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

