/**
 * @notice Script to check what roles an address has in the FP1155 contract
 *
 * @example Check roles for an address
 * ts-node tools/fp/check-roles.ts --network testnet --address 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function hasRole(bytes32 role, address account) external view returns (bool)",
  "function DEFAULT_ADMIN_ROLE() external pure returns (bytes32)",
  "function SEASON_ADMIN_ROLE() external pure returns (bytes32)",
  "function MINTER_ROLE() external pure returns (bytes32)",
  "function TRANSFER_AGENT_ROLE() external pure returns (bytes32)",
  "function PAUSER_ROLE() external pure returns (bytes32)",
  "function CLAIM_SIGNER_ROLE() external pure returns (bytes32)",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl =
    args.rpc ||
    process.env.RPC_URL ||
    process.env.BSC_TESTNET_RPC_URL ||
    process.env.BSC_RPC_URL;
  if (!rpcUrl)
    throw new Error(
      "Missing RPC URL (set --rpc or RPC_URL/BSC_TESTNET_RPC_URL/BSC_RPC_URL)"
    );
  const provider = new ethers.JsonRpcProvider(rpcUrl);

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

  const address = args.address || args.to;
  if (!address) throw new Error("Missing --address (or --to)");
  if (!ethers.isAddress(address)) throw new Error("Invalid address format");

  const fp1155 = new ethers.Contract(contract, ABI, provider);

  console.log(`Checking roles for ${address} on contract ${contract}\n`);

  const roles = [
    { name: "DEFAULT_ADMIN_ROLE", getter: () => fp1155.DEFAULT_ADMIN_ROLE() },
    { name: "SEASON_ADMIN_ROLE", getter: () => fp1155.SEASON_ADMIN_ROLE() },
    { name: "MINTER_ROLE", getter: () => fp1155.MINTER_ROLE() },
    { name: "TRANSFER_AGENT_ROLE", getter: () => fp1155.TRANSFER_AGENT_ROLE() },
    { name: "PAUSER_ROLE", getter: () => fp1155.PAUSER_ROLE() },
    { name: "CLAIM_SIGNER_ROLE", getter: () => fp1155.CLAIM_SIGNER_ROLE() },
  ];

  for (const role of roles) {
    const roleHash = await role.getter();
    const hasRole = await fp1155.hasRole(roleHash, address);
    console.log(`${role.name}: ${hasRole ? "✓ YES" : "✗ NO"}`);
    if (hasRole) {
      console.log(`  Hash: ${roleHash}`);
    }
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




