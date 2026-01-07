/**
 * Script to set claim ready status of an event
 * npm run set-claim-ready -- <eventId> <true|false>
 * 
 * Examples:
 * npm run set-claim-ready -- ufc-323 true   (enable claims)
 * npm run set-claim-ready -- ufc-323 false  (disable claims)
 */
import { getBooster } from "./booster-client";

async function main() {
  const [eventId, claimReadyStr] = process.argv.slice(2);
  
  if (!eventId || claimReadyStr === undefined) {
    console.error("Usage: npm run set-claim-ready -- <eventId> <true|false>");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    console.error("  claimReady: true to enable claims, false to disable");
    process.exit(1);
  }

  // Parse boolean value
  const claimReady = claimReadyStr.toLowerCase() === "true" || claimReadyStr === "1";
  
  const booster = await getBooster();
  
  console.log(`Setting claim ready of event ${eventId} to ${claimReady}`);
  const tx = await booster.setEventClaimReady(eventId, claimReady);
  console.log("Tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log(`✓ Claim ready set to ${claimReady} in block ${receipt.blockNumber}`);
  
  // Verify status after transaction
  const getEventFunc = booster.getFunction("getEvent");
  const [, , , currentClaimReady] = await getEventFunc(eventId);
  console.log(`Current event status: claimReady = ${currentClaimReady}`);
}

main().catch(console.error);
