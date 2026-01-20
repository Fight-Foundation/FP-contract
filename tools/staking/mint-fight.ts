/**
 * @notice Script to mint FIGHT tokens for staking testing
 *
 * @example Mint 1M tokens to default address (0xa6B215709D47B853cC44aa177F18B627Df0eee25)
 * ts-node tools/staking/mint-fight.ts --network testnet --amount 1000000
 *
 * @example Mint to custom address
 * ts-node tools/staking/mint-fight.ts --network testnet --to 0xYourAddress --amount 1000000
 */
import "dotenv/config";
import { ethers } from "ethers";

const ERC20_ABI = [
  "function mint(address to, uint256 amount) external",
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)",
];

// Default recipient address for staking
const DEFAULT_RECIPIENT = "0xa6B215709D47B853cC44aa177F18B627Df0eee25";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  
  const rpcUrl =
    args.rpc ||
    process.env.RPC_URL ||
    process.env.TESTNET_BSC_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or RPC_URL/TESTNET_BSC_RPC_URL/BSC_RPC_URL)"
    );
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing PRIVATE_KEY in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const networkName = (args.network || args.net || "").toLowerCase();
  const fightTokenAddress =
    args.contract ||
    args.fight ||
    (networkName === "testnet"
      ? process.env.TESTNET_FIGHT_TOKEN_ADDRESS || process.env.FIGHT_TOKEN_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_FIGHT_TOKEN_ADDRESS || process.env.FIGHT_TOKEN_ADDRESS
      : process.env.FIGHT_TOKEN_ADDRESS);
  
  if (!fightTokenAddress) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_FIGHT_TOKEN_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_FIGHT_TOKEN_ADDRESS"
        : "FIGHT_TOKEN_ADDRESS";
    throw new Error(`Missing FIGHT token address (set --contract or ${envVar} in .env)`);
  }

  // Get recipient address (default or from args)
  const toAddress = args.to || args.address || DEFAULT_RECIPIENT;
  if (!ethers.isAddress(toAddress)) throw new Error("Invalid address format");

  // Parse amount - can be in human-readable format (e.g., "1000000") or wei format
  const amountInput = args.amount;
  if (!amountInput) throw new Error("Missing --amount");

  const fightToken = new ethers.Contract(fightTokenAddress, ERC20_ABI, wallet);

  // Get token info
  const decimals = await fightToken.decimals();
  const symbol = await fightToken.symbol();

  let mintAmount: bigint;
  // Check if amount is in human-readable format (e.g., "1000000") or wei format
  if (amountInput.includes(".") || /^\d+$/.test(amountInput)) {
    // Human-readable format, convert to wei
    mintAmount = ethers.parseUnits(amountInput, decimals);
  } else {
    // Already in wei format
    mintAmount = BigInt(amountInput);
  }

  if (mintAmount <= 0n) throw new Error("--amount must be > 0");

  console.log(`\n=== Minting FIGHT Tokens for Staking ===`);
  console.log(`FIGHT contract: ${fightTokenAddress}`);
  console.log(`Recipient: ${toAddress}`);
  console.log(`From wallet: ${wallet.address}`);
  console.log(`Network: ${networkName || "default"}`);
  console.log(`Amount: ${ethers.formatUnits(mintAmount, decimals)} ${symbol} (${mintAmount.toString()} wei)\n`);

  // Check current balance
  const balanceBefore = await fightToken.balanceOf(toAddress);
  console.log(`Current balance: ${ethers.formatUnits(balanceBefore, decimals)} ${symbol}\n`);

  // Mint tokens
  console.log("Sending mint transaction...");
  const tx = await fightToken.mint(toAddress, mintAmount);
  console.log("Submitted mint tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify new balance
  const balanceAfter = await fightToken.balanceOf(toAddress);
  console.log(`\n✓ Mint complete!`);
  console.log(`\n=== Updated Balance ===`);
  console.log(`New balance: ${ethers.formatUnits(balanceAfter, decimals)} ${symbol}`);
  console.log(`Minted: ${ethers.formatUnits(balanceAfter - balanceBefore, decimals)} ${symbol}`);
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
