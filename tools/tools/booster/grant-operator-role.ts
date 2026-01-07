/**
 * @notice Script to grant OPERATOR_ROLE to an address in the Booster contract
 *
 * @example Grant role to operator
 * ts-node tools/booster/grant-operator-role.ts --network testnet --to 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8
 * 
 * @example With custom private key
 * ts-node tools/booster/grant-operator-role.ts --network testnet --to 0x0c1cd337cb3e57bb5f21161c7c6744e30057db50 --privateKey 0x...
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function grantRole(bytes32 role, address account) external",
  "function hasRole(bytes32 role, address account) external view returns (bool)",
  "function OPERATOR_ROLE() external pure returns (bytes32)",
  "function DEFAULT_ADMIN_ROLE() external view returns (bytes32)",
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
  
  // Get private key from argument or env
  const pk = args.privateKey || args.pk || process.env.PRIVATE_KEY_ADMIN || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing private key (set --privateKey or PRIVATE_KEY_ADMIN/PRIVATE_KEY in .env)");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  // Verify network
  const network = await provider.getNetwork();
  console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`);
  
  if (networkName === "testnet" && Number(network.chainId) !== 97) {
    console.error(`⚠️  Warning: Expected BSC Testnet (Chain ID: 97), but connected to Chain ID: ${network.chainId}`);
  } else if (networkName === "testnet") {
    console.log(`✓ Connected to BSC Testnet`);
  }

  console.log(`Using wallet: ${wallet.address}`);
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

  const toAddress = args.to || args.address;
  if (!toAddress) throw new Error("Missing --to (or --address)");
  if (!ethers.isAddress(toAddress)) throw new Error("Invalid address format");

  const booster = new ethers.Contract(contract, ABI, wallet);

  // Get role constants
  const OPERATOR_ROLE = await booster.OPERATOR_ROLE();
  const DEFAULT_ADMIN_ROLE = await booster.DEFAULT_ADMIN_ROLE();

  // Check if wallet has admin role
  const hasAdminRole = await booster.hasRole(DEFAULT_ADMIN_ROLE, wallet.address);
  if (!hasAdminRole) {
    console.error(`❌ Error: Wallet ${wallet.address} does not have DEFAULT_ADMIN_ROLE`);
    console.error(`   Only DEFAULT_ADMIN_ROLE can grant OPERATOR_ROLE`);
    process.exit(1);
  }
  console.log(`✓ Wallet has DEFAULT_ADMIN_ROLE`);

  // Check if already has role
  const hasRole = await booster.hasRole(OPERATOR_ROLE, toAddress);
  if (hasRole) {
    console.log(`✓ Address ${toAddress} already has OPERATOR_ROLE`);
    return;
  }

  console.log(`\nGranting OPERATOR_ROLE to ${toAddress}...`);
  console.log(`OPERATOR_ROLE: ${OPERATOR_ROLE}`);
  const tx = await booster.grantRole(OPERATOR_ROLE, toAddress);
  console.log("Submitted grantRole tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);

  // Verify
  const nowHasRole = await booster.hasRole(OPERATOR_ROLE, toAddress);
  if (nowHasRole) {
    console.log(`✓ Successfully granted OPERATOR_ROLE to ${toAddress}`);
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

