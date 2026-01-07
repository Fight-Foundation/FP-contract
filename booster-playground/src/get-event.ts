/**
 * Script to get event information
 * npm run get-event -- <eventId>
 * 
 * Examples:
 * npm run get-event -- ufc-323
 * npm run get-event -- ufc-323
 */
import { getBoosterReadOnly } from "./booster-client";

async function main() {
  const [eventId] = process.argv.slice(2);
  
  if (!eventId) {
    console.error("Usage: npm run get-event -- <eventId>");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    process.exit(1);
  }

  console.log(`\n=== Getting event information: ${eventId} ===\n`);

  const booster = getBoosterReadOnly();

  try {
    const getEventFunc = booster.getFunction("getEvent");
    const [seasonId, numFights, exists, claimReady] = await getEventFunc(eventId);
    
    console.log(`Season ID: ${seasonId.toString()}`);
    console.log(`Number of fights: ${numFights.toString()}`);
    console.log(`Exists: ${exists}`);
    console.log(`Claim ready: ${claimReady}`);
    
    if (!exists) {
      console.log("\n⚠️  Event does not exist");
      process.exit(1);
    }
    
    console.log("\n✓ Event exists");
    
    const deadline = await booster.getEventClaimDeadline(eventId);
    console.log(`Claim deadline: ${deadline > 0 ? new Date(Number(deadline) * 1000).toLocaleString() : "No limit"}`);
    
    const isClaimReady = await booster.isEventClaimReady(eventId);
    console.log(`Is claim ready: ${isClaimReady}`);
    
    const [fightIds] = await booster.getEventFights(eventId);
    console.log(`Fights: ${fightIds.length} (IDs: ${fightIds.map((id: any) => id.toString()).join(", ")})`);
    
  } catch (error: any) {
    console.error("\n❌ Error:", error.message);
    process.exit(1);
  }
}

main().catch(console.error);
