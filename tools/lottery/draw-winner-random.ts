/**
 * @notice Script to randomly draw a winner for a DailyLottery round
 *         Shows all entries with their indices, performs a random draw,
 *         and prepares the transaction with console approval
 *
 * @example Draw winner with FP prize on testnet (random selection)
 * ts-node tools/lottery/draw-winner-random.ts --network testnet --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000
 *
 * @example Draw winner with FP prize on mainnet (random selection)
 * ts-node tools/lottery/draw-winner-random.ts --network mainnet --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000
 *
 * @example Draw winner with ERC20 prize (random selection)
 * ts-node tools/lottery/draw-winner-random.ts --network testnet --dayId 20444 --prizeType ERC20 --prizeToken 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd --prizeAmount 1000000000000000000 (1 USDT)
 *
 * @example With custom contract address and RPC URL
 * ts-node tools/lottery/draw-winner-random.ts --contract 0x123... --rpc https://bsc-testnet.publicnode.com --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000
 */
import "dotenv/config";
import { ethers } from "ethers";
import * as readline from "readline";
import * as fs from "fs";
import * as path from "path";

const ABI = [
  "function drawWinner(uint256 dayId, uint256 winningIndex, tuple(uint8 prizeType, address tokenAddress, uint256 seasonId, uint256 amount) prize) external",
  "function getCurrentDayId() external view returns (uint256)",
  "function getLotteryRound(uint256 dayId) external view returns (tuple(uint256 dayId, uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser, uint256 totalEntries, uint256 totalPaid, address winner, bool finalized, uint8 prizeType, address prizeTokenAddress, uint256 prizeSeasonId, uint256 prizeAmount))",
  "function getEntries(uint256 dayId) external view returns (address[])",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint8)",
];

const FP1155_ABI = [
  "function setApprovalForAll(address operator, bool approved) external",
  "function isApprovedForAll(address account, address operator) external view returns (bool)",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

enum PrizeType {
  FP = 0,
  ERC20 = 1,
}

// Helper function to create readline interface for user input
function createReadlineInterface(): readline.Interface {
  return readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
}

// Helper function to ask for user confirmation
function askConfirmation(rl: readline.Interface, question: string): Promise<boolean> {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === "y" || normalized === "yes" || normalized === "s" || normalized === "si");
    });
  });
}

// Generate random number between min (inclusive) and max (exclusive)
function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min)) + min;
}

// Logger class to capture console output and save to file
class Logger {
  private logs: string[] = [];
  private originalLog: typeof console.log;

  constructor() {
    this.originalLog = console.log;
    // Override console.log to capture output
    console.log = (...args: any[]) => {
      const message = args.map(arg => 
        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
      ).join(' ');
      this.logs.push(message);
      this.originalLog(...args);
    };
  }

  getLogs(): string {
    return this.logs.join('\n');
  }

  saveToFile(filePath: string): void {
    const content = this.getLogs();
    fs.writeFileSync(filePath, content, 'utf-8');
  }

  restore(): void {
    console.log = this.originalLog;
  }
}

async function main() {
  // Initialize logger to capture all output
  const logger = new Logger();
  globalLogger = logger; // Store reference for error handling
  
  const args = parseArgs(process.argv.slice(2));
  
  // Determine RPC URL based on network selection or fallback
  let rpcUrl: string | undefined = args.rpc;
  
  // If --network is specified, use network-specific env vars
  if (!rpcUrl && args.network) {
    const network = args.network.toLowerCase();
    if (network === "mainnet" || network === "main") {
      rpcUrl = process.env.BSC_RPC_URL || process.env.MAINNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else if (network === "testnet" || network === "test") {
      rpcUrl = process.env.BSC_TESTNET_RPC_URL || process.env.TESTNET_BSC_RPC_URL || process.env.RPC_URL || undefined;
    } else {
      throw new Error(`Invalid network: ${args.network}. Use 'mainnet' or 'testnet'`);
    }
  }
  
  // Fallback to default priority if no network specified
  if (!rpcUrl) {
    rpcUrl =
      process.env.TESTNET_BSC_RPC_URL ||
      process.env.RPC_URL ||
      process.env.BSC_TESTNET_RPC_URL ||
      process.env.BSC_RPC_URL ||
      undefined;
  }
  
  if (!rpcUrl) {
    console.error("❌ Missing RPC URL");
    console.error("\nOptions:");
    console.error("  1. Pass as argument: --rpc <URL>");
    console.error("  2. Use network flag: --network mainnet|testnet");
    console.error(
      "  3. Set in .env file: BSC_RPC_URL (mainnet), BSC_TESTNET_RPC_URL (testnet), or RPC_URL"
    );
    console.error("\nExamples:");
    console.error(
      "  ts-node tools/lottery/draw-winner-random.ts --network testnet --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000"
    );
    console.error(
      "  ts-node tools/lottery/draw-winner-random.ts --network mainnet --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000"
    );
    console.error(
      "  ts-node tools/lottery/draw-winner-random.ts --rpc https://bsc-testnet.publicnode.com --dayId 20440 --prizeType FP --prizeSeasonId 323 --prizeAmount 1000"
    );
    process.exit(1);
  }
  
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  
  // Detect and display network info
  const network = await provider.getNetwork();
  const networkName = network.chainId === 56n ? "BSC Mainnet" : network.chainId === 97n ? "BSC Testnet" : `Chain ID ${network.chainId}`;
  console.log(`🌐 Network: ${networkName} (Chain ID: ${network.chainId})`);

  const pk = process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing OPERATOR_PK (or PRIVATE_KEY) in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const contract = args.contract || process.env.LOTTERY_ADDRESS;
  if (!contract)
    throw new Error("Missing contract (set --contract or LOTTERY_ADDRESS)");

  const lottery = new ethers.Contract(contract, ABI, wallet);

  // Parse arguments
  const dayId = args.dayId ? BigInt(args.dayId) : await lottery.getCurrentDayId();

  const prizeTypeStr = args.prizeType?.toUpperCase() || "FP";
  const prizeType = prizeTypeStr === "FP" ? PrizeType.FP : PrizeType.ERC20;

  let prizeTokenAddress = args.prizeToken || "0x0000000000000000000000000000000000000000";
  let prizeSeasonId = BigInt(args.prizeSeasonId ?? args.season ?? 0);
  let prizeAmount = BigInt(args.prizeAmount ?? args.amount ?? 0);

  if (prizeAmount === 0n) {
    throw new Error("Missing --prizeAmount (or --amount)");
  }

  if (prizeType === PrizeType.ERC20 && prizeTokenAddress === "0x0000000000000000000000000000000000000000") {
    throw new Error("Missing --prizeToken for ERC20 prize");
  }

  if (prizeType === PrizeType.FP && prizeSeasonId === 0n) {
    throw new Error("Missing --prizeSeasonId (or --season) for FP prize");
  }

  console.log("=== Lottery Winner Draw (Random) ===");
  console.log(`Lottery Address: ${contract}`);
  console.log(`Admin: ${wallet.address}`);
  console.log(`Day ID: ${dayId}`);

  // Get round info
  const round = await lottery.getLotteryRound(dayId);

  if (round.dayId === 0n) {
    throw new Error(`Round for day ${dayId} doesn't exist yet`);
  }

  if (round.finalized) {
    throw new Error(`Round for day ${dayId} is already finalized. Winner: ${round.winner}`);
  }

  if (round.totalEntries === 0n) {
    throw new Error(`Round for day ${dayId} has no entries`);
  }

  console.log(`\n=== Round Information ===`);
  console.log(`Total Entries: ${round.totalEntries}`);
  console.log(`Season ID: ${round.seasonId}`);
  console.log(`Entry Price: ${round.entryPrice} FP`);
  console.log(`Max Entries Per User: ${round.maxEntriesPerUser}`);
  console.log(`Total Paid: ${round.totalPaid} FP`);

  // Get all entries
  const entries = await lottery.getEntries(dayId);
  const totalEntries = Number(round.totalEntries);

  console.log(`\n=== All Entries (${totalEntries} total) ===`);
  console.log("Index | Address");
  console.log("------|----------------------------------------");
  
  // Show all entries with their indices
  entries.forEach((addr: string, index: number) => {
    console.log(`${String(index).padStart(5)} | ${addr}`);
  });

  // Show summary by address
  const entryCounts: Record<string, number> = {};
  entries.forEach((addr: string) => {
    entryCounts[addr] = (entryCounts[addr] || 0) + 1;
  });

  const uniqueAddresses = Array.from(new Set(entries)) as string[];
  console.log(`\n=== Summary by Address ===`);
  uniqueAddresses.forEach((addr: string) => {
    const count = entryCounts[addr];
    const indices: number[] = [];
    entries.forEach((e: string, i: number) => {
      if (e.toLowerCase() === addr.toLowerCase()) {
        indices.push(i);
      }
    });
    console.log(`${addr}: ${count} entry${count > 1 ? "ies" : ""} at indices [${indices.join(", ")}]`);
  });

  // Perform random draw
  const winningIndex = randomInt(0, totalEntries);
  const winner = entries[winningIndex];

  console.log(`\n=== Random Draw Result ===`);
  console.log(`Winning Index: ${winningIndex}`);
  console.log(`Winner Address: ${winner}`);

  // Prize info
  console.log("\n=== Prize Configuration ===");
  console.log(`Prize Type: ${prizeTypeStr}`);
  
  let needsApproval = false;

  if (prizeType === PrizeType.FP) {
    console.log(`Prize Season ID: ${prizeSeasonId}`);
    const fpTokenAddress = process.env.FP_TOKEN_ADDRESS || "0xb3a5bCbE34fe7Ff56A7d6E0d1fC683A130eBDA41";
    const fpToken = new ethers.Contract(
      fpTokenAddress,
      FP1155_ABI,
      wallet
    );
    
    // Check admin balance
    const adminBalance = await fpToken.balanceOf(wallet.address, prizeSeasonId);
    console.log(`Admin FP Balance (Season ${prizeSeasonId}): ${adminBalance}`);
    
    if (adminBalance < prizeAmount) {
      throw new Error(`Insufficient FP balance. Have: ${adminBalance}, Need: ${prizeAmount}`);
    }
    
    // Check approval
    const isApproved = await fpToken.isApprovedForAll(wallet.address, contract);
    if (!isApproved) {
      needsApproval = true;
      console.log(`\n⚠️  FP approval needed. Approving lottery contract...`);
      console.log(`   Contract: ${fpTokenAddress}`);
      const approveTx = await fpToken.setApprovalForAll(contract, true);
      console.log(`   Approval tx: ${approveTx.hash}`);
      await approveTx.wait();
      console.log(`✅ FP approval granted`);
    } else {
      console.log(`✅ FP approval already granted`);
    }
  } else {
    console.log(`Prize Token: ${prizeTokenAddress}`);
    const token = new ethers.Contract(prizeTokenAddress, ERC20_ABI, wallet);
    
    // Check admin balance
    const adminBalance = await token.balanceOf(wallet.address);
    const symbol = await token.symbol();
    const decimals = await token.decimals();
    const formattedAmount = ethers.formatUnits(prizeAmount, decimals);
    console.log(`Admin ${symbol} Balance: ${adminBalance} (${formattedAmount} ${symbol})`);
    
    if (adminBalance < prizeAmount) {
      throw new Error(`Insufficient ${symbol} balance. Have: ${adminBalance}, Need: ${prizeAmount}`);
    }
    
    // Check approval and approve if needed
    const currentAllowance = await token.allowance(wallet.address, contract);
    if (currentAllowance < prizeAmount) {
      needsApproval = true;
      console.log(`\n⚠️  ERC20 approval needed. Current allowance: ${currentAllowance}`);
      console.log(`   Approving lottery contract for ${prizeAmount}...`);
      const approveTx = await token.approve(contract, prizeAmount);
      console.log(`   Approval tx: ${approveTx.hash}`);
      await approveTx.wait();
      console.log(`✅ ERC20 approval granted`);
    } else {
      console.log(`✅ ERC20 approval already granted`);
    }
  }

  console.log(`Prize Amount: ${prizeAmount}`);

  // Prepare prize data
  const prize = {
    prizeType: prizeType,
    tokenAddress: prizeTokenAddress,
    seasonId: prizeSeasonId,
    amount: prizeAmount,
  };

  // Show transaction summary
  console.log("\n=== Transaction Summary ===");
  console.log(`Function: drawWinner`);
  console.log(`Parameters:`);
  console.log(`  - dayId: ${dayId}`);
  console.log(`  - winningIndex: ${winningIndex}`);
  console.log(`  - prize:`);
  console.log(`      prizeType: ${prizeType} (${prizeTypeStr})`);
  console.log(`      tokenAddress: ${prizeTokenAddress}`);
  console.log(`      seasonId: ${prizeSeasonId}`);
  console.log(`      amount: ${prizeAmount}`);

  // Ask for confirmation
  const rl = createReadlineInterface();
  const confirm = await askConfirmation(
    rl,
    "\n⚠️  Do you want to submit the drawWinner transaction? (y/n): "
  );
  rl.close();

  if (!confirm) {
    console.log("Transaction cancelled.");
    
    // Save summary even if cancelled
    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = `lottery-draw-${dayId}-${timestamp}-CANCELLED.txt`;
      const outputDir = path.join(process.cwd(), 'tools', 'lottery', 'logs');
      
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      
      const filePath = path.join(outputDir, fileName);
      logger.saveToFile(filePath);
      console.log(`\n📄 Summary saved to: ${filePath}`);
    } catch (error) {
      console.error(`\n⚠️  Failed to save summary file: ${error}`);
    } finally {
      logger.restore();
    }
    
    process.exit(0);
  }

  // Draw winner
  console.log("\n=== Drawing Winner ===");
  const tx = await lottery.drawWinner(dayId, winningIndex, prize);
  console.log("Submitted drawWinner tx:", tx.hash);

  const rcpt = await tx.wait();
  console.log("✅ Mined in block", rcpt.blockNumber);

  // Get updated round info
  const roundAfter = await lottery.getLotteryRound(dayId);

  console.log("\n=== Winner Drawn Successfully ===");
  console.log(`Winner: ${roundAfter.winner}`);
  console.log(`Finalized: ${roundAfter.finalized}`);
  console.log(`Prize Type: ${prizeTypeStr}`);
  console.log(`Prize Amount: ${roundAfter.prizeAmount}`);
  if (prizeType === PrizeType.FP) {
    console.log(`Prize Season ID: ${roundAfter.prizeSeasonId}`);
  } else {
    console.log(`Prize Token: ${roundAfter.prizeTokenAddress}`);
  }

  // Save summary to file
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `lottery-draw-${dayId}-${timestamp}.txt`;
    const outputDir = path.join(process.cwd(), 'tools', 'lottery', 'logs');
    
    // Create logs directory if it doesn't exist
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    const filePath = path.join(outputDir, fileName);
    logger.saveToFile(filePath);
    console.log(`\n📄 Summary saved to: ${filePath}`);
  } catch (error) {
    console.error(`\n⚠️  Failed to save summary file: ${error}`);
  } finally {
    // Restore original console.log
    logger.restore();
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

// Global logger reference for error handling
let globalLogger: Logger | null = null;

main().catch((err) => {
  console.error(err);
  
  // Try to save summary even on error
  if (globalLogger) {
    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = `lottery-draw-ERROR-${timestamp}.txt`;
      const outputDir = path.join(process.cwd(), 'tools', 'lottery', 'logs');
      
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      
      const filePath = path.join(outputDir, fileName);
      globalLogger.saveToFile(filePath);
      console.error(`\n📄 Error summary saved to: ${filePath}`);
    } catch (saveError) {
      console.error(`\n⚠️  Failed to save error summary: ${saveError}`);
    } finally {
      globalLogger.restore();
    }
  }
  
  process.exit(1);
});

