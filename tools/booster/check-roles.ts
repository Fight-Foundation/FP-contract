/**
 * @notice Script to check what roles an address has in the Booster contract
 *
 * @example Check roles for an address
 * ts-node tools/booster/check-roles.ts --network testnet --address 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function hasRole(bytes32 role, address account) external view returns (bool)",
  "function DEFAULT_ADMIN_ROLE() external pure returns (bytes32)",
  "function OPERATOR_ROLE() external pure returns (bytes32)",
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

  const networkName = (args.network || args.net || "").toLowerCase();
  const contract =
    args.contract ||
    (networkName === "testnet"
      ? process.env.TESTNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
      : networkName === "mainnet"
      ? process.env.MAINNET_BOOSTER_ADDRESS || process.env.BOOSTER_ADDRESS
      : process.env.BOOSTER_ADDRESS);
  if (!contract) {
    const envVar =
      networkName === "testnet"
        ? "TESTNET_BOOSTER_ADDRESS"
        : networkName === "mainnet"
        ? "MAINNET_BOOSTER_ADDRESS"
        : "BOOSTER_ADDRESS";
    throw new Error(`Missing contract (set --contract or ${envVar} in .env)`);
  }

  const address = args.address || args.to;
  if (!address) throw new Error("Missing --address (or --to)");
  if (!ethers.isAddress(address)) throw new Error("Invalid address format");

  const booster = new ethers.Contract(contract, ABI, provider);

  console.log(`Checking roles for ${address} on contract ${contract}\n`);

  const roles = [
    { name: "DEFAULT_ADMIN_ROLE", getter: () => booster.DEFAULT_ADMIN_ROLE() },
    { name: "OPERATOR_ROLE", getter: () => booster.OPERATOR_ROLE() },
  ];

  for (const role of roles) {
    const roleHash = await role.getter();
    const hasRole = await booster.hasRole(roleHash, address);
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












