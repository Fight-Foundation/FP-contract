/**
 * @notice Script to stake and unstake FIGHT tokens
 *
 * @example Stake 100 tokens (1e20 = 100 * 1e18)
 * ts-node tools/tools/staking/stake.ts --network testnet --action stake --amount 100
 *
 * @example Unstake 50 tokens
 * ts-node tools/tools/staking/stake.ts --network testnet --action unstake --amount 50
 *
 * @example Check balance
 * ts-node tools/tools/staking/stake.ts --network testnet --action balance
 */
import "dotenv/config";
import { ethers } from "ethers";

const STAKING_ABI = [
  "function stake(uint256 amount) external",
  "function unstake(uint256 amount) external",
  "function balances(address user) external view returns (uint256)",
  "function totalStaked() external view returns (uint256)",
  "function paused() external view returns (bool)",
  "function FIGHT_TOKEN() external view returns (address)",
];

const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const action = (args.action || "").toLowerCase();
  
  if (!action || !["stake", "unstake", "balance"].includes(action)) {
    throw new Error("Missing or invalid --action (must be: stake, unstake, or balance)");
  }

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

  const pk = process.env.USER_PK;
  if (!pk) throw new Error("Missing USER_PK in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const networkName = (args.network || args.net || "").toLowerCase();
  const stakingAddress =
    args.contract ||
    args.staking ||
    (networkName === "testnet"
      ? process.env.TESTNET_STAKING_ADDRESS || process.env.STAKING_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_STAKING_ADDRESS || process.env.STAKING_ADDRESS
      : process.env.STAKING_ADDRESS);
  
  if (!stakingAddress) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_STAKING_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_STAKING_ADDRESS"
        : "STAKING_ADDRESS";
    throw new Error(`Missing staking contract (set --contract or ${envVar} in .env)`);
  }

  const staking = new ethers.Contract(stakingAddress, STAKING_ABI, wallet);

  // Get FIGHT token address
  const fightTokenAddress = await staking.FIGHT_TOKEN();
  const fightToken = new ethers.Contract(fightTokenAddress, ERC20_ABI, wallet);

  // Get token info
  const decimals = await fightToken.decimals();
  const symbol = await fightToken.symbol();

  console.log(`\n=== Staking Contract Info ===`);
  console.log(`Staking contract: ${stakingAddress}`);
  console.log(`FIGHT token: ${fightTokenAddress} (${symbol})`);
  console.log(`User wallet: ${wallet.address}`);
  console.log(`Network: ${networkName || "default"}\n`);

  // Check if paused
  const isPaused = await staking.paused();
  if (isPaused && action === "stake") {
    throw new Error("Contract is paused. Cannot stake.");
  }
  console.log(`Contract paused: ${isPaused}\n`);

  // Get balances
  const tokenBalance = await fightToken.balanceOf(wallet.address);
  const stakedBalance = await staking.balances(wallet.address);
  const totalStaked = await staking.totalStaked();

  console.log(`=== Current Balances ===`);
  console.log(`${symbol} balance: ${ethers.formatUnits(tokenBalance, decimals)} ${symbol}`);
  console.log(`Staked balance: ${ethers.formatUnits(stakedBalance, decimals)} ${symbol}`);
  console.log(`Total staked: ${ethers.formatUnits(totalStaked, decimals)} ${symbol}\n`);

  if (action === "balance") {
    console.log("✓ Balance check complete");
    return;
  }

  // Parse amount
  const amountInput = args.amount;
  if (!amountInput) throw new Error("Missing --amount");
  
  let amount: bigint;
  // Check if amount is in human-readable format (e.g., "100") or wei format
  if (amountInput.includes(".") || /^\d+$/.test(amountInput)) {
    // Human-readable format, convert to wei
    amount = ethers.parseUnits(amountInput, decimals);
  } else {
    // Already in wei format
    amount = BigInt(amountInput);
  }

  if (amount <= 0n) throw new Error("--amount must be > 0");

  console.log(`=== Transaction Details ===`);
  console.log(`Action: ${action}`);
  console.log(`Amount: ${ethers.formatUnits(amount, decimals)} ${symbol} (${amount.toString()} wei)\n`);

  if (action === "stake") {
    // Check balance
    if (tokenBalance < amount) {
      throw new Error(
        `Insufficient ${symbol} balance: have ${ethers.formatUnits(tokenBalance, decimals)}, need ${ethers.formatUnits(amount, decimals)}`
      );
    }

    // Check and approve if needed
    const allowance = await fightToken.allowance(wallet.address, stakingAddress);
    if (allowance < amount) {
      console.log(`Approving ${symbol}...`);
      const approveAmount = amount * 2n; // Approve a bit more to avoid multiple approvals
      const approveTx = await fightToken.approve(stakingAddress, approveAmount);
      console.log("Submitted approve tx:", approveTx.hash);
      await approveTx.wait();
      console.log("✓ Approval confirmed\n");
    } else {
      console.log(`✓ Sufficient allowance: ${ethers.formatUnits(allowance, decimals)} ${symbol}\n`);
    }

    // Stake
    console.log("Sending stake transaction...");
    const tx = await staking.stake(amount);
    console.log("Submitted stake tx:", tx.hash);
    const rcpt = await tx.wait();
    console.log("Mined in block", rcpt.blockNumber);

    // Verify new balances
    const newTokenBalance = await fightToken.balanceOf(wallet.address);
    const newStakedBalance = await staking.balances(wallet.address);
    const newTotalStaked = await staking.totalStaked();

    console.log(`\n✓ Stake complete!`);
    console.log(`\n=== Updated Balances ===`);
    console.log(`${symbol} balance: ${ethers.formatUnits(newTokenBalance, decimals)} ${symbol}`);
    console.log(`Staked balance: ${ethers.formatUnits(newStakedBalance, decimals)} ${symbol}`);
    console.log(`Total staked: ${ethers.formatUnits(newTotalStaked, decimals)} ${symbol}`);
  } else if (action === "unstake") {
    // Check staked balance
    if (stakedBalance < amount) {
      throw new Error(
        `Insufficient staked balance: have ${ethers.formatUnits(stakedBalance, decimals)}, need ${ethers.formatUnits(amount, decimals)}`
      );
    }

    // Unstake
    console.log("Sending unstake transaction...");
    const tx = await staking.unstake(amount);
    console.log("Submitted unstake tx:", tx.hash);
    const rcpt = await tx.wait();
    console.log("Mined in block", rcpt.blockNumber);

    // Verify new balances
    const newTokenBalance = await fightToken.balanceOf(wallet.address);
    const newStakedBalance = await staking.balances(wallet.address);
    const newTotalStaked = await staking.totalStaked();

    console.log(`\n✓ Unstake complete!`);
    console.log(`\n=== Updated Balances ===`);
    console.log(`${symbol} balance: ${ethers.formatUnits(newTokenBalance, decimals)} ${symbol}`);
    console.log(`Staked balance: ${ethers.formatUnits(newStakedBalance, decimals)} ${symbol}`);
    console.log(`Total staked: ${ethers.formatUnits(newTotalStaked, decimals)} ${symbol}`);
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
