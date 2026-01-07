/**
 * Script to place a boost
 * 
 * Option 1: On behalf of user (use PRIVATE_KEY_USER from .env)
 * npm run place-boost -- userPk <eventId> <fightId> <amount> <winner> <method>
 * 
 * Option 2: On behalf of operator (use PRIVATE_KEY from .env)
 * npm run place-boost -- operatorPk <eventId> <fightId> <amount> <winner> <method>
 * 
 * Examples:
 * npm run place-boost -- userPk ufc-323 1 1000000 0 0     (user)
 * npm run place-boost -- operatorPk ufc-323 1 1000000 0 0 (operator)
 */
import "dotenv/config";
import { ethers } from "ethers";
import boosterAbi from "./booster-abi.json";
import { getBoosterReadOnly } from "./booster-client";

const TESTNET_BOOSTER_ADDRESS = "0xdcA538E7385dc39888f8934D7D3e9E6beE2E8DEf";
const DEFAULT_RPC = "https://data-seed-prebsc-1-s1.binance.org:8545/";

// Minimal ERC1155 ABI for balanceOf
const ERC1155_ABI = [
  "function balanceOf(address account, uint256 id) external view returns (uint256)"
];

async function main() {
  const args = process.argv.slice(2);
  
  // Detect if first argument is "userPk" or "operatorPk"
  let userPk: string | undefined;
  let eventId: string;
  let fightId: string;
  let amount: string;
  let winner: string;
  let method: string;

  if (args[0] === "userPk") {
    // User mode: use PRIVATE_KEY_USER from .env
    [, eventId, fightId, amount, winner, method] = args;
    userPk = process.env.PRIVATE_KEY_USER;
  } else if (args[0] === "operatorPk") {
    // Operator mode: use PRIVATE_KEY or PRIVATE_KEY_OPERATOR from .env
    [, eventId, fightId, amount, winner, method] = args;
    userPk = process.env.PRIVATE_KEY || process.env.PRIVATE_KEY_OPERATOR;
  } else {
    // Incorrect format
    console.error("Error: First argument must be 'userPk' or 'operatorPk'");
    console.error("Usage (user mode): npm run place-boost -- userPk <eventId> <fightId> <amount> <winner> <method>");
    console.error("Usage (operator mode): npm run place-boost -- operatorPk <eventId> <fightId> <amount> <winner> <method>");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    console.error("  fightId: Fight ID (1, 2, 3, ...)");
    console.error("  amount: Amount of FP tokens to bet");
    console.error("  winner: 0=RED, 1=BLUE");
    console.error("  method: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION");
    process.exit(1);
  }
  
  if (!eventId || !fightId || !amount || winner === undefined || method === undefined) {
    console.error("Error: Missing required arguments");
    console.error("Usage (user mode): npm run place-boost -- userPk <eventId> <fightId> <amount> <winner> <method>");
    console.error("Usage (operator mode): npm run place-boost -- operatorPk <eventId> <fightId> <amount> <winner> <method>");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    console.error("  fightId: Fight ID (1, 2, 3, ...)");
    console.error("  amount: Amount of FP tokens to bet");
    console.error("  winner: 0=RED, 1=BLUE");
    console.error("  method: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION");
    process.exit(1);
  }

  if (!userPk) {
    const mode = args[0] === "userPk" ? "PRIVATE_KEY_USER" : "PRIVATE_KEY or PRIVATE_KEY_OPERATOR";
    console.error(`Error: ${mode} not found in .env file`);
    process.exit(1);
  }

  const rpcUrl = process.env.TESTNET_BSC_RPC_URL || DEFAULT_RPC;
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // Create wallet (user or operator)
  const wallet = new ethers.Wallet(
    userPk.startsWith("0x") ? userPk : "0x" + userPk,
    provider
  );

  const mode = args[0] === "userPk" ? "user" : "operator";
  
  console.log(`Mode: ${mode}`);
  console.log(`Wallet: ${wallet.address}`);
  console.log(`Event: ${eventId}, Fight: ${fightId}`);
  console.log(`Amount: ${amount}, Winner: ${winner} (${winner === "0" ? "RED" : "BLUE"}), Method: ${method}`);

  // Get seasonId from event and check balance
  const boosterReadOnly = getBoosterReadOnly();
  const getEventFunc = boosterReadOnly.getFunction("getEvent");
  const [seasonId] = await getEventFunc(eventId);
  
  // Check balance in FP1155
  const fp1155Address = process.env.TESTNET_FP1155_ADDRESS;
  if (!fp1155Address) {
    console.error("Error: TESTNET_FP1155_ADDRESS not found in .env file");
    process.exit(1);
  }
  
  const fp1155 = new ethers.Contract(
    ethers.getAddress(fp1155Address.trim().replace(/['"]/g, '')),
    ERC1155_ABI,
    provider
  );
  
  const balance = await fp1155.balanceOf(wallet.address, seasonId);
  const amountBigInt = BigInt(amount);
  
  console.log(`\nBalance check:`);
  console.log(`  Season ID: ${seasonId.toString()}`);
  console.log(`  Current balance: ${balance.toString()} FP`);
  console.log(`  Required amount: ${amountBigInt.toString()} FP`);
  
  if (balance < amountBigInt) {
    console.error(`\n❌ Insufficient balance: you have ${balance.toString()} FP, need ${amountBigInt.toString()} FP`);
    process.exit(1);
  }
  
  console.log(`✓ Sufficient balance\n`);

  const booster = new ethers.Contract(
    ethers.getAddress(TESTNET_BOOSTER_ADDRESS.trim().replace(/['"]/g, '')),
    boosterAbi,
    wallet
  );

  // Create boost input
  const boostInput = {
    fightId: BigInt(fightId),
    amount: BigInt(amount),
    predictedWinner: parseInt(winner),
    predictedMethod: parseInt(method)
  };

  console.log("\nSending boost...");
  const tx = await booster.placeBoosts(eventId, [boostInput]);
  console.log("Tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("✓ Boost placed in block", receipt.blockNumber);
  
  // Find BoostPlaced event to get index
  const boostPlacedEvent = receipt.logs.find((log: any) => {
    try {
      const parsed = booster.interface.parseLog(log);
      return parsed?.name === "BoostPlaced";
    } catch {
      return false;
    }
  });

  if (boostPlacedEvent) {
    try {
      const parsed = booster.interface.parseLog(boostPlacedEvent);
      console.log(`✓ Boost index: ${parsed?.args[3]?.toString()}`);
    } catch (e) {
      // Ignore if cannot parse
    }
  }
}

main().catch(console.error);
