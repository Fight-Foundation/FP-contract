/**
 * @notice Script to grant CLAIM_SIGNER_ROLE to an address in the FP1155 contract
 *
 * @example Grant role to claim signer
 * ts-node tools/fp/grant-claim-signer-role.ts --network testnet --to 0x76C0BC9b0322E971D5A98F8f64e103715462C0A9
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function grantRole(bytes32 role, address account) external",
  "function hasRole(bytes32 role, address account) external view returns (bool)",
  "function CLAIM_SIGNER_ROLE() external pure returns (bytes32)",
];

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
  const contract =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_FP1155_ADDRESS || process.env.FP1155_ADDRESS
      : process.env.FP1155_ADDRESS);
  if (!contract) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_FP1155_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_FP1155_ADDRESS"
        : "FP1155_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  const toAddress = args.to || args.address;
  if (!toAddress) throw new Error("Missing --to (or --address)");
  if (!ethers.isAddress(toAddress)) throw new Error("Invalid address format");

  const fp1155 = new ethers.Contract(contract, ABI, wallet);

  // Get the role hash
  const CLAIM_SIGNER_ROLE = await fp1155.CLAIM_SIGNER_ROLE();
  console.log(`CLAIM_SIGNER_ROLE: ${CLAIM_SIGNER_ROLE}`);

  // Check if already has role
  const hasRole = await fp1155.hasRole(CLAIM_SIGNER_ROLE, toAddress);
  if (hasRole) {
    console.log(`✓ Address ${toAddress} already has CLAIM_SIGNER_ROLE`);
    return;
  }

  console.log(`Granting CLAIM_SIGNER_ROLE to ${toAddress}...`);
  const tx = await fp1155.grantRole(CLAIM_SIGNER_ROLE, toAddress);
  console.log("Submitted grantRole tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify
  const nowHasRole = await fp1155.hasRole(CLAIM_SIGNER_ROLE, toAddress);
  if (nowHasRole) {
    console.log(`✓ Successfully granted CLAIM_SIGNER_ROLE to ${toAddress}`);
  } else {
    console.log(`✗ Warning: Role grant may have failed (check transaction)`);
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



