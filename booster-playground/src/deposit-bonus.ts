/**
 * Script to deposit bonus
 * npm run deposit-bonus -- ufc-323 1 1000000
 */
import { getBooster } from "./booster-client";

async function main() {
  const [eventId, fightId, amount] = process.argv.slice(2);
  
  if (!eventId || !fightId || !amount) {
    console.error("Usage: npm run deposit-bonus -- <eventId> <fightId> <amount>");
    process.exit(1);
  }

  const booster = await getBooster();
  console.log(`Depositing ${amount} bonus to fight ${fightId} of event ${eventId}`);
  const tx = await booster.depositBonus(eventId, BigInt(fightId), BigInt(amount), false);
  console.log("Tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("✓ Bonus deposited in block", receipt.blockNumber);
}

main().catch(console.error);
