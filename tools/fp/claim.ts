/**
 * @notice Script to sign and execute a claim for FP tokens
 *
 * @example Claim 1000 tokens for season 323 using USER_PK
 * ts-node tools/fp/claim.ts --season 323 --amount 1000
 * 
 * @example Claim using OPERATOR_PK
 * ts-node tools/fp/claim.ts --operator --season 323 --amount 1000
 * 
 * Note: This script only works on BSC Testnet (chainId 97).
 * The user who receives tokens is always the wallet from USER_PK or OPERATOR_PK.
 */
import "dotenv/config";
import { ethers } from "ethers";

const READ_ABI = [
  "function nonces(address) view returns (uint256)",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

const WRITE_ABI = [
  "function claim(uint256 seasonId, uint256 amount, uint256 deadline, bytes calldata signature) external",
  "function nonces(address) view returns (uint256)",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = (typeof args.rpc === "string" ? args.rpc : undefined) || process.env.TESTNET_BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or TESTNET_BSC_RPC_URL in .env). This script only works on testnet."
    );
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // Wallet for signing the claim (server with CLAIM_SIGNER_ROLE)
  const signerPk = process.env.CLAIM_SIGNER_PK || process.env.PRIVATE_KEY;
  if (!signerPk)
    throw new Error("Missing CLAIM_SIGNER_PK (or PRIVATE_KEY) in .env");
  const signerWallet = new ethers.Wallet(
    signerPk.startsWith("0x") ? signerPk : "0x" + signerPk,
    provider
  );

  // Wallet for executing the claim (user who will receive tokens)
  // Use --operator flag to use OPERATOR_PK, otherwise use USER_PK
  const useOperator = !!args.operator || !!args.op;
  const userPk = useOperator
    ? process.env.OPERATOR_PK
    : process.env.USER_PK;
  if (!userPk) {
    const envVar = useOperator ? "OPERATOR_PK" : "USER_PK";
    throw new Error(
      `Missing ${envVar} in .env. This should be the wallet of the user claiming tokens.`
    );
  }
  const userWallet = new ethers.Wallet(
    userPk.startsWith("0x") ? userPk : "0x" + userPk,
    provider
  );
  
  // The user address is always the wallet that executes the claim
  const userAddress = userWallet.address;

  // Verify we're on testnet (BSC Testnet chainId is 97)
  const chainId = (await provider.getNetwork()).chainId;
  if (chainId !== 97n) {
    throw new Error(
      `This script only works on BSC Testnet (chainId 97). Current chainId: ${chainId}`
    );
  }

  const contract = (typeof args.contract === "string" ? args.contract : undefined) || process.env.TESTNET_FP1155_ADDRESS;
  if (!contract) {
    throw new Error(
      "Missing contract (set --contract or TESTNET_FP1155_ADDRESS in .env)"
    );
  }

  const seasonId = BigInt(
    (typeof args.season === "string" ? args.season : typeof args.seasonId === "string" ? args.seasonId : undefined) ?? 0
  );
  if (seasonId <= 0n) throw new Error("--season (or --seasonId) must be > 0");

  const amount = BigInt((typeof args.amount === "string" ? args.amount : undefined) ?? 0);
  if (amount <= 0n) throw new Error("--amount must be > 0");

  // Calculate deadline if not provided (default: 1 day from now)
  const deadline =
    typeof args.deadline === "string"
      ? BigInt(args.deadline)
      : BigInt(Math.floor(Date.now() / 1000) + 86400); // 1 day from now
  if (deadline <= 0n) throw new Error("--deadline must be > 0");

  const fpReadOnly = new ethers.Contract(contract, READ_ABI, provider);
  const nonce = await fpReadOnly.nonces(userAddress);

  const walletType = useOperator ? "OPERATOR" : "USER";
  
  console.log("Claim Details:");
  console.log("─".repeat(60));
  console.log(`Contract: ${contract}`);
  console.log(`User: ${userAddress} (${walletType})`);
  console.log(`Season ID: ${seasonId.toString()}`);
  console.log(`Amount: ${amount.toString()}`);
  console.log(`Nonce: ${nonce.toString()}`);
  console.log(`Deadline: ${deadline.toString()} (${new Date(Number(deadline) * 1000).toISOString()})`);
  console.log(`Signer: ${signerWallet.address}`);
  console.log(`Executor: ${userWallet.address} (${walletType})`);
  console.log();

  // Sign the claim
  const domain = {
    name: "FP1155",
    version: "1",
    chainId,
    verifyingContract: contract,
  } as const;

  const types = {
    Claim: [
      { name: "account", type: "address" },
      { name: "seasonId", type: "uint256" },
      { name: "amount", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  } as const;

  const message = {
    account: userAddress,
    seasonId,
    amount,
    nonce,
    deadline,
  } as const;

  console.log("Signing claim...");
  const signature = await signerWallet.signTypedData(
    domain as any,
    types as any,
    message as any
  );
  console.log(`✓ Signature generated: ${signature.slice(0, 20)}...`);

  // Check balance before claim
  const fpWrite = new ethers.Contract(contract, WRITE_ABI, userWallet);
  const balanceBefore = await fpReadOnly.balanceOf(userAddress, seasonId);
  console.log(`\nBalance before claim: ${balanceBefore.toString()}`);

  // Execute the claim
  console.log(`\nExecuting claim transaction...`);
  const tx = await fpWrite.claim(seasonId, amount, deadline, signature);
  console.log(`Submitted claim tx: ${tx.hash}`);
  const rcpt = await tx.wait();
  console.log(`✓ Mined in block ${rcpt.blockNumber}`);

  // Verify new balance
  const balanceAfter = await fpReadOnly.balanceOf(userAddress, seasonId);
  console.log(`\n✓ Claim complete!`);
  console.log(`Balance after claim: ${balanceAfter.toString()}`);
  console.log(`Tokens claimed: ${(balanceAfter - balanceBefore).toString()}`);
}

function parseArgs(argv: string[]) {
  const out: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      // Handle boolean flags (no value)
      if (i + 1 >= argv.length || argv[i + 1].startsWith("--")) {
        out[key] = true;
      } else {
        const val = argv[i + 1];
        out[key] = val;
        i++;
      }
    }
  }
  return out;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

