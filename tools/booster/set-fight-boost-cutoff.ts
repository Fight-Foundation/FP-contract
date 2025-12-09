/**
 * @notice Script to set the boost cutoff timestamp for a fight (after which new boosts are rejected)
 *
 * How to calculate Unix timestamp:
 * - Current timestamp in terminal (Mac/Linux): date +%s
 * - Specific date in terminal (Mac): date -j -f "%Y-%m-%d %H:%M:%S" "2024-01-01 00:00:00" +%s
 * - Specific date in terminal (Linux): date -d "2024-01-01 00:00:00" +%s
 * - Using Node.js (current time): node -e "console.log(Math.floor(Date.now() / 1000))"
 * - Using Node.js (specific date): node -e "console.log(Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000))"
 * - Online converter: https://www.epochconverter.com/
 *
 * @example Set cutoff to a specific unix timestamp
 * ts-node tools/booster/set-fight-boost-cutoff.ts --eventId UFC_300 --fightId 1 --cutoff 1704067200
 *
 * @example Calculate timestamp for 1 hour from now (using Node.js)
 * node -e "console.log(Math.floor(Date.now() / 1000) + 3600)"
 *
 * @example Calculate timestamp for a specific date (e.g., Jan 1, 2024 00:00:00 UTC)
 * node -e "console.log(Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000))"
 *
 * @example Disable cutoff (set to 0, relies on status only)
 * ts-node tools/booster/set-fight-boost-cutoff.ts --eventId UFC_300 --fightId 1 --cutoff 0
 *
 * @example Using alternative parameter names
 * ts-node tools/booster/set-fight-boost-cutoff.ts --event UFC_300 --fight 1 --timestamp 1704067200
 *
 * @example With custom contract address
 * ts-node tools/booster/set-fight-boost-cutoff.ts --contract 0x123... --eventId UFC_300 --fightId 1 --cutoff 1704067200
 */
import "dotenv/config";
import { ethers } from "ethers";

const ABI = [
  "function setFightBoostCutoff(string calldata eventId, uint256 fightId, uint256 cutoff) external",
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

  const pk = process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Missing OPERATOR_PK (or PRIVATE_KEY) in .env");
  const wallet = new ethers.Wallet(
    pk.startsWith("0x") ? pk : "0x" + pk,
    provider
  );

  const contract = args.contract || process.env.BOOSTER_ADDRESS;
  if (!contract)
    throw new Error("Missing contract (set --contract or BOOSTER_ADDRESS)");

  const eventId = args.eventId || args.event;
  if (!eventId) throw new Error("Missing --eventId (or --event)");

  const fightId = BigInt(args.fightId ?? args.fight ?? 0);
  if (fightId <= 0n) throw new Error("--fightId (or --fight) must be > 0");

  const cutoff = args.cutoff || args.timestamp;
  if (!cutoff) throw new Error("Missing --cutoff (or --timestamp)");
  const cutoffBigInt = BigInt(cutoff);

  const booster = new ethers.Contract(contract, ABI, wallet);
  console.log(
    `Setting boost cutoff for event: ${eventId}, fightId: ${fightId}, cutoff: ${cutoffBigInt}`
  );
  const tx = await booster.setFightBoostCutoff(eventId, fightId, cutoffBigInt);
  console.log("Submitted setFightBoostCutoff tx:", tx.hash);
  const rcpt = await tx.wait();
  console.log("Mined in block", rcpt.blockNumber);
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
