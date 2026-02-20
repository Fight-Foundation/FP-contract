import "dotenv/config";
import { ethers } from "ethers";

export interface BoosterConfig {
  networkMode: "mainnet" | "testnet" | "custom";
  provider: ethers.JsonRpcProvider;
  wallet?: ethers.Wallet;
  contractAddress: string;
}

export function parseArgs(argv: string[]) {
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

export async function setupBoosterConfig(args: Record<string, string>, requireWallet = false): Promise<BoosterConfig> {
  const networkName = (args.network || args.net || "").toLowerCase();
  
  // Determine RPC URL based on network parameter
  let rpcUrl: string | undefined = args.rpc;
  if (!rpcUrl) {
    if (networkName === "mainnet") {
      rpcUrl = process.env.MAINNET_BSC_RPC_URL || process.env.RPC_URL;
    } else if (networkName === "testnet") {
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL;
    } else {
      // Default to testnet logic if not specified, or fallback
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL;
    }
  }
  
  if (!rpcUrl) {
     const envVar = networkName === "mainnet" 
      ? "MAINNET_BSC_RPC_URL" 
      : networkName === "testnet"
      ? "TESTNET_BSC_RPC_URL"
      : "TESTNET_BSC_RPC_URL or RPC_URL";
    throw new Error(`Missing RPC URL (set --rpc or ${envVar} in .env)`);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  
  let wallet: ethers.Wallet | undefined;
  if (requireWallet) {
      const pk = process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
      if (!pk) throw new Error("Missing OPERATOR_PK (or PRIVATE_KEY) in .env");
      wallet = new ethers.Wallet(pk.startsWith("0x") ? pk : "0x" + pk, provider);
  }

  const contractAddress =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
      : process.env.BOOSTER_ADDRESS);

  if (!contractAddress) {
     const envVar =
      networkName === "testnet"
        ? "TESTNET_BOOSTER_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_BOOSTER_ADDRESS"
        : "BOOSTER_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  let networkMode: "mainnet" | "testnet" | "custom" = "custom";
  if (networkName === "mainnet") networkMode = "mainnet";
  if (networkName === "testnet") networkMode = "testnet";

  return {
      networkMode,
      provider,
      wallet,
      contractAddress
  };
}
