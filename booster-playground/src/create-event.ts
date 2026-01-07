/**
 * Script to create an event
 * npm run create-event -- ufc-324 10 323 1765062000
 */
import { getBooster } from "./booster-client";

async function main() {
  const [eventId, numFights, seasonId, cutoff] = process.argv.slice(2);
  
  if (!eventId || !numFights || !seasonId) {
    console.error("Usage: npm run create-event -- <eventId> <numFights> <seasonId> [cutoff]");
    process.exit(1);
  }

  const booster = await getBooster();
  const defaultCutoff = cutoff ? BigInt(cutoff) : 0n;

  console.log(`Creating event: ${eventId}, fights: ${numFights}, season: ${seasonId}, cutoff: ${defaultCutoff}`);
  const tx = await booster.createEvent(eventId, BigInt(numFights), BigInt(seasonId), defaultCutoff);
  console.log("Tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("✓ Event created in block", receipt.blockNumber);
}

main().catch(console.error);
