/**
 * @notice Script to deposit bonus FP tokens to a fight's prize pool
 *
 * @example Using testnet
 * ts-node tools/booster/deposit-bonus.ts --network testnet --eventId UFC_300 --fightId 1 --amount 5000000000000000000
 *
 * @example Using mainnet
 * ts-node tools/booster/deposit-bonus.ts --network mainnet --eventId UFC_300 --fightId 1 --amount 5000000000000000000
 *
 * @example Deposit 5 FP (5e18 wei) as bonus for fight 1
 * ts-node tools/booster/deposit-bonus.ts --network testnet --eventId UFC_300 --fightId 1 --amount 5000000000000000000
 *
 * @example Deposit 10 FP for fight 3
 * ts-node tools/booster/deposit-bonus.ts --network testnet --eventId UFC_300 --fightId 3 --amount 10000000000000000000
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/deposit-bonus.ts --network testnet --event UFC_300 --fight 1 --amount 5000000000000000000
 *
 * @example With custom contract address
 * ts-node tools/booster/deposit-bonus.ts --contract 0x123... --eventId UFC_300 --fightId 1 --amount 5000000000000000000
 *
 * @example Skip confirmation prompt
 * ts-node tools/booster/deposit-bonus.ts --network testnet --eventId UFC_300 --fightId 1 --amount 5000000000000000000 --yes
 *
 * @env MAINNET_BSC_EXPLORER_URL - Block explorer URL for BSC Mainnet (default: https://bscscan.com)
 * @env TESTNET_BSC_EXPLORER_URL - Block explorer URL for BSC Testnet (default: https://testnet.bscscan.com)
 */
import "dotenv/config";
import { ethers } from "ethers";
import {
  parseArgs,
  setupBoosterConfig,
  displayTransactionSummary,
  requestConfirmation,
  waitForTransaction,
} from "./booster.utils";

const ABI = [
  "function depositBonus(string calldata eventId, uint256 fightId, uint256 amount) external",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = await setupBoosterConfig(args);

  // Log network mode for clarity
  console.log(`Network mode: ${config.networkMode.toUpperCase()}`);

  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error("Missing --eventId (or --event)");

  const fightId = BigInt(args.fightId ?? args.fight ?? 0);
  if (fightId <= 0n) throw new Error("--fightId (or --fight) must be > 0");

  const amount = args.amount;
  if (!amount) throw new Error("Missing --amount");
  const amountBigInt = BigInt(amount);
  if (amountBigInt <= 0n) throw new Error("--amount must be > 0");

  const booster = new ethers.Contract(config.contractAddress, ABI, config.wallet);

  // Format amount for display (convert from wei to FP)
  const amountInFP = ethers.formatEther(amountBigInt);

  // Display transaction summary
  displayTransactionSummary(config, [
    `Event ID: ${eventId}`,
    `Fight ID: ${fightId}`,
    `Amount: ${amountInFP} FP (${amountBigInt} wei)`,
  ], "depositBonus");

  // Request confirmation
  await requestConfirmation(args);

  console.log("\n🚀 Executing transaction...");
  const tx = await booster.depositBonus(eventId, fightId, amountBigInt);
  await waitForTransaction(tx, config.chainId);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
