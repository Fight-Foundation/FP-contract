/**
 * @notice Portable client to interact with Booster contract on testnet
 * 
 * @example
 * import { getBooster } from './booster-client';
 * 
 * const booster = await getBooster();
 * const tx = await booster.createEvent('ufc-324', 10, 323, 1765062000);
 * await tx.wait();
 */
import "dotenv/config";
import { ethers } from "ethers";
import boosterAbi from "./booster-abi.json";


/**
 * Gets a Booster contract instance connected to testnet
 */
export async function getBooster(): Promise<ethers.Contract> {
  const rpcUrl = process.env.BSC_TESTNET_RPC_URL;
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.PRIVATE_KEY_OPERATOR || process.env.OPERATOR_PK;
  if (!pk) {
    throw new Error("Missing PRIVATE_KEY_OPERATOR or OPERATOR_PK in .env");
  }

  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const contractAddress = process.env.TESTNET_BOOSTER_ADDRESS;    
  if (!contractAddress) {
    throw new Error("Missing TESTNET_BOOSTER_ADDRESS in .env");
  }
  // Normalize address to prevent ethers from attempting ENS resolution
  const normalizedAddress = ethers.getAddress(contractAddress.trim().replace(/['"]/g, ''));
  return new ethers.Contract(normalizedAddress, boosterAbi, wallet);
}

/**
 * Gets only the provider (without wallet) for read-only calls
 */
export function getProvider(): ethers.JsonRpcProvider {
  const rpcUrl = process.env.BSC_TESTNET_RPC_URL;
  return new ethers.JsonRpcProvider(rpcUrl);
}

/**
 * Gets a Booster contract instance in read-only mode
 */
export function getBoosterReadOnly(): ethers.Contract {
  const contractAddress = process.env.TESTNET_BOOSTER_ADDRESS;
  if (!contractAddress) {
    throw new Error("Missing TESTNET_BOOSTER_ADDRESS in .env");
  }
  // Normalize address to prevent ethers from attempting ENS resolution
  const normalizedAddress = ethers.getAddress(contractAddress.trim().replace(/['"]/g, ''));
  return new ethers.Contract(normalizedAddress, boosterAbi, getProvider());
}
