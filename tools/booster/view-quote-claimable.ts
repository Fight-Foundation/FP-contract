/**
 * @notice Script to view claimable quote for a specific user and multiple fights
 *
 * @example Using testnet
 * ts-node tools/booster/view-quote-claimable.ts --network testnet --eventId ufc-323 --user 0x123...
 * ts-node tools/booster/view-quote-claimable.ts --network mainnet --eventId ufc-324 --user 0x078Fb5219dD6b416408A10Dc4aD78565E1642bB3
 *
 * @example Using mainnet
 * ts-node tools/booster/view-quote-claimable.ts --network mainnet --eventId UFC_300 --user 0x123...
 */
import "dotenv/config";
import { ethers } from "ethers";
import { setupBoosterConfig, parseArgs } from "./booster.utils";

const ABI = [
  "function quoteClaimable(string calldata eventId, uint256 fightId, address user, bool enforceDeadline) external view returns (uint256 totalClaimable)",
];

function formatEther(wei: bigint): string {
  return `${ethers.formatEther(wei)} FP`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  
  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error("Missing --eventId (or --event)");

  const user = args.user;
  if (!user) throw new Error("Missing --user address");

  const startFight = parseInt(args.start || "1");
  const endFight = parseInt(args.end || "10");

  const config = await setupBoosterConfig(args);
  
  // Get network information for display
  const network = await config.provider.getNetwork();
  const chainId = Number(network.chainId);
  let actualNetwork: string = chainId === 56 ? "BSC Mainnet" : chainId === 97 ? "BSC Testnet" : network.name || `Chain ID ${chainId}`;

  console.log(`Network: ${actualNetwork}`);
  console.log(`Contract: ${config.contractAddress}`);
  console.log(`Event ID: ${eventId}`);
  console.log(`User: ${user}\n`);

  const booster = new ethers.Contract(config.contractAddress, ABI, config.provider);

  console.log("📊 Claimable Quotes (Fights ${startFight} to ${endFight}):");
  console.log("─".repeat(60));

  let totalAllFights = 0n;

  for (let fightId = startFight; fightId <= endFight; fightId++) {
    try {
      const claimable = await booster.quoteClaimable(eventId, fightId, user, false);
      const claimableBigInt = BigInt(claimable.toString());
      totalAllFights += claimableBigInt;
      
      console.log(`  Fight ID ${fightId.toString().padEnd(2)}: ${formatEther(claimableBigInt)}`);
    } catch (error: any) {
      let reason = "Error";
      if (error.reason) reason = error.reason;
      else if (error.message && error.message.includes("execution reverted")) {
        // Try to extract simple reason if possible, or just say reverted
        reason = "Reverted (Stakes might not be resolved or no stakes)";
      }
      console.log(`  Fight ID ${fightId.toString().padEnd(2)}: ${reason}`);
    }
  }

  console.log("─".repeat(60));
  console.log(`Total Claimable: ${formatEther(totalAllFights)}`);
  console.log("\n✅ Query completed successfully");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
