/**
 * @notice Script to view today's lottery entries and round info
 *
 * @example
 * ts-node tools/lottery/view-entries.ts
 *
 * @example With custom contract address
 * ts-node tools/lottery/view-entries.ts --contract 0x123...
 *
 * @example On mainnet (default)
 * ts-node tools/lottery/view-entries.ts --network mainnet
 *
 * @example On testnet
 * ts-node tools/lottery/view-entries.ts --network testnet
 *
 * @example With custom RPC URL
 * ts-node tools/lottery/view-entries.ts --rpc https://bsc-dataseed.binance.org
 *
 * @example View a specific day
 * ts-node tools/lottery/view-entries.ts --dayId 20505
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function getCurrentDayId() external view returns (uint256)",
  "function getTotalEntries(uint256 dayId) external view returns (uint256)",
  "function getLotteryRound(uint256 dayId) external view returns (tuple(uint256 dayId, uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser, uint256 totalEntries, uint256 totalPaid, address winner, bool finalized, uint8 prizeType, address prizeTokenAddress, uint256 prizeSeasonId, uint256 prizeAmount))",
  "function defaultSeasonId() external view returns (uint256)",
  "function defaultEntryPrice() external view returns (uint256)",
  "function defaultMaxEntriesPerUser() external view returns (uint256)",
  "function defaultMaxFreeEntriesPerUser() external view returns (uint256)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const networkName = args.network || "mainnet";

  let rpcUrl: string | undefined = args.rpc;
  if (!rpcUrl) {
    if (networkName === "mainnet") {
      rpcUrl = process.env.MAINNET_BSC_RPC_URL || process.env.BSC_RPC_URL;
    } else if (networkName === "testnet") {
      rpcUrl = process.env.TESTNET_BSC_RPC_URL || process.env.BSC_TESTNET_RPC_URL;
    }
    rpcUrl = rpcUrl || process.env.RPC_URL;
  }
  if (!rpcUrl) {
    console.error("Missing RPC URL");
    console.error("\nOptions:");
    console.error("  1. Pass --network mainnet|testnet");
    console.error("  2. Pass --rpc <URL>");
    console.error("  3. Set in .env: MAINNET_BSC_RPC_URL, TESTNET_BSC_RPC_URL, or RPC_URL");
    process.exit(1);
  }
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const contract = args.contract || process.env.LOTTERY_ADDRESS;
  if (!contract)
    throw new Error("Missing contract (set --contract or LOTTERY_ADDRESS)");

  const lottery = new ethers.Contract(contract, ABI, provider);

  // Get current day ID from contract
  const currentDayId = await lottery.getCurrentDayId();
  const dayId = args.dayId ? BigInt(args.dayId) : currentDayId;

  const isToday = dayId === currentDayId;
  const dateFromDayId = new Date(Number(dayId) * 86400 * 1000);

  console.log("=== Daily Lottery ===");
  console.log(`Contract:    ${contract}`);
  console.log(`Current Day: ${currentDayId} (${new Date(Number(currentDayId) * 86400 * 1000).toUTCString()})`);
  if (!isToday) {
    console.log(`Viewing Day: ${dayId} (${dateFromDayId.toUTCString()})`);
  }

  // Get round info
  const round = await lottery.getLotteryRound(dayId);
  const roundExists = round.dayId === dayId;

  if (!roundExists) {
    const defaultSeason = await lottery.defaultSeasonId();
    const defaultPrice = await lottery.defaultEntryPrice();
    const defaultMax = await lottery.defaultMaxEntriesPerUser();
    const defaultMaxFree = await lottery.defaultMaxFreeEntriesPerUser();

    console.log("\n--- Round not created yet (no entries) ---");
    console.log(`Defaults: Season ${defaultSeason} | Price ${defaultPrice} FP | Max ${defaultMax} entries/user | Max Free ${defaultMaxFree}/user`);
    console.log("Total Tickets: 0");
    return;
  }

  console.log(`\n=== Round Info (Day ${dayId}) ===`);
  console.log(`Season ID:          ${round.seasonId}`);
  console.log(`Entry Price:        ${round.entryPrice} FP`);
  console.log(`Max Entries/User:   ${round.maxEntriesPerUser}`);
  console.log(`Max Free/User:      ${round.maxFreeEntriesPerUser}`);
  console.log(`Total FP Burned:    ${round.totalPaid}`);
  console.log(`Finalized:          ${round.finalized}`);
  if (round.finalized) {
    console.log(`Winner:             ${round.winner}`);
    const prizeType = round.prizeType === 0 ? "FP" : "ERC20";
    console.log(`Prize:              ${round.prizeAmount} ${prizeType}${round.prizeType === 1 ? ` (${round.prizeTokenAddress})` : ` (Season ${round.prizeSeasonId})`}`);
  }

  console.log(`\n=== Tickets ===`);
  console.log(`Total Tickets:      ${round.totalEntries}`);
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
