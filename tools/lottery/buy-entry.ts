/**
 * @notice Script to buy an entry in the DailyLottery contract
 *
 * @example
 * ts-node tools/lottery/buy-entry.ts
 *
 * @example With custom contract address
 * ts-node tools/lottery/buy-entry.ts --contract 0x123...
 *
 * @example With custom RPC URL
 * ts-node tools/lottery/buy-entry.ts --rpc https://bsc-testnet.publicnode.com
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function buyEntry() external",
  "function getCurrentDayId() external view returns (uint256)",
  "function getUserEntries(uint256 dayId, address user) external view returns (uint256)",
  "function getTotalEntries(uint256 dayId) external view returns (uint256)",
  "function getLotteryRound(uint256 dayId) external view returns (tuple(uint256 dayId, uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 totalEntries, uint256 totalPaid, address winner, bool finalized, uint8 prizeType, address prizeTokenAddress, uint256 prizeSeasonId, uint256 prizeAmount))",
  "function defaultSeasonId() external view returns (uint256)",
  "function defaultEntryPrice() external view returns (uint256)",
  "function defaultMaxEntriesPerUser() external view returns (uint256)",
];

const FP1155_ABI = [
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl =
    args.rpc ||
    process.env.TESTNET_BSC_RPC_URL ||
    process.env.RPC_URL ||
    process.env.BSC_TESTNET_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl) {
    console.error("❌ Missing RPC URL");
    console.error("\nOptions:");
    console.error("  1. Pass as argument: --rpc <URL>");
    console.error("  2. Set in .env file: TESTNET_BSC_RPC_URL, RPC_URL, BSC_TESTNET_RPC_URL, or BSC_RPC_URL");
    console.error("\nExample:");
    console.error("  ts-node tools/lottery/buy-entry.ts --rpc https://bsc-testnet.publicnode.com");
    process.exit(1);
  }
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.USER_PK;
  if (!pk) throw new Error("Missing USER_PK in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const contract = args.contract || process.env.LOTTERY_ADDRESS;
  if (!contract)
    throw new Error("Missing contract (set --contract or LOTTERY_ADDRESS)");

  const lottery = new ethers.Contract(contract, ABI, wallet);

  // Get current day ID
  const dayId = await lottery.getCurrentDayId();
  console.log(`Current Day ID: ${dayId}`);

  // Get round info before buying
  let round = await lottery.getLotteryRound(dayId);
  
  // If round doesn't exist (dayId = 0), get defaults from contract
  if (round.dayId === 0n) {
    const defaultSeasonId = await lottery.defaultSeasonId();
    const defaultEntryPrice = await lottery.defaultEntryPrice();
    const defaultMaxEntries = await lottery.defaultMaxEntriesPerUser();
    
    round = {
      dayId: dayId,
      seasonId: defaultSeasonId,
      entryPrice: defaultEntryPrice,
      maxEntriesPerUser: defaultMaxEntries,
      totalEntries: 0n,
      totalPaid: 0n,
      winner: "0x0000000000000000000000000000000000000000",
      finalized: false,
      prizeType: 0,
      prizeTokenAddress: "0x0000000000000000000000000000000000000000",
      prizeSeasonId: 0n,
      prizeAmount: 0n,
    };
  }

  const userEntriesBefore = await lottery.getUserEntries(dayId, wallet.address);
  const totalEntriesBefore = await lottery.getTotalEntries(dayId);

  console.log("\n=== Round Info ===");
  console.log(`Season ID: ${round.seasonId}`);
  console.log(`Entry Price: ${round.entryPrice} FP`);
  console.log(`Max Entries Per User: ${round.maxEntriesPerUser}`);
  console.log(`Total Entries: ${totalEntriesBefore}`);
  console.log(`Your Entries: ${userEntriesBefore}/${round.maxEntriesPerUser}`);

  // Check if round exists (dayId will be 0 if round doesn't exist)
  if (Number(round.dayId) === 0) {
    console.log("⚠️  Round doesn't exist yet. It will be auto-created when you buy an entry.");
  }

  // Check if user can buy more entries
  if (userEntriesBefore >= round.maxEntriesPerUser) {
    throw new Error(
      `Maximum entries reached (${round.maxEntriesPerUser}). Cannot buy more entries.`
    );
  }

  if (round.finalized) {
    throw new Error("Round is already finalized. Cannot buy entries.");
  }

  // Check FP token balance
  const fpTokenAddress = process.env.FP_TOKEN_ADDRESS || "0xb3a5bCbE34fe7Ff56A7d6E0d1fC683A130eBDA41";
  const fpToken = new ethers.Contract(fpTokenAddress, FP1155_ABI, provider);
  
  const fpBalance = await fpToken.balanceOf(wallet.address, round.seasonId);
  
  console.log("\n=== User Status ===");
  console.log(`Address: ${wallet.address}`);
  console.log(`FP Balance (Season ${round.seasonId}): ${fpBalance}`);
  
  if (fpBalance < round.entryPrice) {
    throw new Error(
      `Insufficient FP balance. You have ${fpBalance} FP but need ${round.entryPrice} FP to buy an entry.`
    );
  }

  console.log(`\nBuying entry (will burn ${round.entryPrice} FP tokens)...`);
  const tx = await lottery.buyEntry();
  console.log("Submitted buyEntry tx:", tx.hash);

  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Get updated info
  const userEntriesAfter = await lottery.getUserEntries(dayId, wallet.address);
  const totalEntriesAfter = await lottery.getTotalEntries(dayId);

  console.log("\n=== Entry Purchased ===");
  console.log(`Your Entries: ${userEntriesAfter}/${round.maxEntriesPerUser}`);
  console.log(`Total Entries: ${totalEntriesAfter}`);
  console.log(`Burned: ${round.entryPrice} FP tokens`);
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

