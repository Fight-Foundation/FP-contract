/**
 * Script to set cutoff
 * npm run set-cutoff -- event ufc-323 1765062000
 * npm run set-cutoff -- fight ufc-323 1 1765062000
 */
import { getBooster } from "./booster-client";

async function main() {
  const [type, eventId, ...rest] = process.argv.slice(2);
  
  if (type === "event") {
    const [cutoff] = rest;
    if (!eventId || !cutoff) {
      console.error("Usage: npm run set-cutoff -- event <eventId> <cutoff>");
      process.exit(1);
    }
    const booster = await getBooster();
    console.log(`Setting cutoff of event ${eventId} to ${cutoff}`);
    const tx = await booster.setEventBoostCutoff(eventId, BigInt(cutoff));
    console.log("Tx hash:", tx.hash);
    const receipt = await tx.wait();
    console.log("✓ Cutoff set in block", receipt.blockNumber);
  } else if (type === "fight") {
    const [fightId, cutoff] = rest;
    if (!eventId || !fightId || !cutoff) {
      console.error("Usage: npm run set-cutoff -- fight <eventId> <fightId> <cutoff>");
      process.exit(1);
    }
    const booster = await getBooster();
    console.log(`Setting cutoff of fight ${fightId} from event ${eventId} to ${cutoff}`);
    const tx = await booster.setFightBoostCutoff(eventId, BigInt(fightId), BigInt(cutoff));
    console.log("Tx hash:", tx.hash);
    const receipt = await tx.wait();
    console.log("✓ Cutoff set in block", receipt.blockNumber);
  } else {
    console.error("Usage: npm run set-cutoff -- event <eventId> <cutoff>");
    console.error("   or: npm run set-cutoff -- fight <eventId> <fightId> <cutoff>");
    process.exit(1);
  }
}

main().catch(console.error);
