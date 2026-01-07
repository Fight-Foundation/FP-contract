/**
 * Script to submit fight result
 * npm run submit-result -- ufc-323 1 0 0 3 4 5000000 10000000
 */
import { getBooster } from "./booster-client";

async function main() {
  const [eventId, fightId, winner, method, pointsWinner, pointsWinnerMethod, sumWinnersStakes, winningPoolTotalShares] = process.argv.slice(2);
  
  if (!eventId || !fightId || !winner || !method || !pointsWinner || !pointsWinnerMethod || !sumWinnersStakes || !winningPoolTotalShares) {
    console.error("Usage: npm run submit-result -- <eventId> <fightId> <winner> <method> <pointsWinner> <pointsWinnerMethod> <sumWinnersStakes> <winningPoolTotalShares>");
    console.error("winner: 0=RED, 1=BLUE, 2=NONE");
    console.error("method: 0=KNOCKOUT, 1=SUBMISSION, 2=DECISION, 3=NO_CONTEST");
    process.exit(1);
  }

  const booster = await getBooster();
  console.log(`Submitting result of fight ${fightId} from event ${eventId}`);
  const tx = await booster.submitFightResult(
    eventId,
    BigInt(fightId),
    parseInt(winner),
    parseInt(method),
    BigInt(pointsWinner),
    BigInt(pointsWinnerMethod),
    BigInt(sumWinnersStakes),
    BigInt(winningPoolTotalShares)
  );
  console.log("Tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("✓ Result submitted in block", receipt.blockNumber);
}

main().catch(console.error);
