/**
 * Script to check what is available to claim
 * 
 * Option 1: On behalf of user (use PRIVATE_KEY_USER from .env)
 * npm run check-claimable -- userPk <eventId> [fightId]
 * 
 * Option 2: On behalf of operator (use PRIVATE_KEY from .env)
 * npm run check-claimable -- operatorPk <eventId> [fightId]
 * 
 * Examples:
 * npm run check-claimable -- userPk ufc-323           (all fights)
 * npm run check-claimable -- userPk ufc-323 1         (only fight 1)
 * npm run check-claimable -- operatorPk ufc-323       (operator, all fights)
 */
import "dotenv/config";
import { ethers } from "ethers";
import { getBoosterReadOnly, getProvider } from "./booster-client";

async function main() {
  const args = process.argv.slice(2);
  
  // Detect if first argument is "userPk" or "operatorPk"
  let userAddress: string | undefined;
  let eventId: string;
  let fightId: string | undefined;

  if (args[0] === "userPk") {
    // User mode: get address from PRIVATE_KEY_USER
    const userPk = process.env.PRIVATE_KEY_USER;
    if (!userPk) {
      console.error("Error: PRIVATE_KEY_USER not found in .env file");
      process.exit(1);
    }
    const provider = getProvider();
    const wallet = new ethers.Wallet(
      userPk.startsWith("0x") ? userPk : "0x" + userPk,
      provider
    );
    userAddress = wallet.address;
    [, eventId, fightId] = args;
  } else if (args[0] === "operatorPk") {
    // Operator mode: get address from PRIVATE_KEY_OPERATOR, OPERATOR_PK or PRIVATE_KEY
    const operatorPk = process.env.PRIVATE_KEY_OPERATOR || process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
    if (!operatorPk) {
      console.error("Error: PRIVATE_KEY_OPERATOR, OPERATOR_PK or PRIVATE_KEY not found in .env file");
      process.exit(1);
    }
    const provider = getProvider();
    const wallet = new ethers.Wallet(
      operatorPk.startsWith("0x") ? operatorPk : "0x" + operatorPk,
      provider
    );
    userAddress = wallet.address;
    [, eventId, fightId] = args;
  } else {
    // Incorrect format
    console.error("Error: First argument must be 'userPk' or 'operatorPk'");
    console.error("Usage (user mode): npm run check-claimable -- userPk <eventId> [fightId]");
    console.error("Usage (operator mode): npm run check-claimable -- operatorPk <eventId> [fightId]");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    console.error("  fightId: Specific fight ID (optional, if not specified shows all)");
    process.exit(1);
  }
  
  if (!eventId) {
    console.error("Error: Missing eventId");
    console.error("Usage (user mode): npm run check-claimable -- userPk <eventId> [fightId]");
    console.error("Usage (operator mode): npm run check-claimable -- operatorPk <eventId> [fightId]");
    process.exit(1);
  }

  const mode = args[0] === "userPk" ? "user" : "operator";
  console.log(`\n=== Checking claimable for ${mode} ===`);
  console.log(`Address: ${userAddress}`);
  console.log(`Event: ${eventId}\n`);

  const booster = getBoosterReadOnly();

  // Get event information
  try {
    const getEventFunc = booster.getFunction("getEvent");
    const [seasonId, numFights, exists, claimReady] = await getEventFunc(eventId);
    
    if (!exists) {
      console.error(`Error: Event ${eventId} does not exist`);
      process.exit(1);
    }

    const deadline = await booster.getEventClaimDeadline(eventId);
    const now = Math.floor(Date.now() / 1000);
    
    console.log(`Event information:`);
    console.log(`  Season ID: ${seasonId.toString()}`);
    console.log(`  Number of fights: ${numFights.toString()}`);
    console.log(`  Claim ready: ${claimReady ? "Yes" : "No"}`);
    if (deadline > 0) {
      const deadlineDate = new Date(Number(deadline) * 1000);
      const isExpired = now > Number(deadline);
      console.log(`  Deadline: ${deadlineDate.toLocaleString()} ${isExpired ? "(EXPIRED)" : ""}`);
    } else {
      console.log(`  Deadline: No limit`);
    }
    console.log("");

    // Get list of fights if one was not specified
    let fightsToCheck: bigint[] = [];
    
    if (fightId) {
      // Verify fight exists
      const fightNum = BigInt(fightId);
      if (fightNum < 1 || fightNum > numFights) {
        console.error(`Error: Fight ${fightId} does not exist (valid range: 1-${numFights})`);
        process.exit(1);
      }
      fightsToCheck = [fightNum];
    } else {
      const [fightIds] = await booster.getEventFights(eventId);
      fightsToCheck = fightIds;
    }

    if (fightsToCheck.length === 0) {
      console.log("No fights in this event");
      return;
    }

    // Check claimable for each fight
    let totalClaimable = 0n;
    const results: Array<{
      fightId: bigint;
      status: number;
      claimable: bigint;
      resolved: boolean;
    }> = [];

    for (const fid of fightsToCheck) {
      try {
        const getFightFunc = booster.getFunction("getFight");
        const fight = await getFightFunc(eventId, fid);
        const status = Number(fight[0]); // FightStatus: 0=OPEN, 1=CLOSED, 2=RESOLVED
        const cancelled = fight[11];
        
        // Only check claimable if fight is resolved
        const isResolved = status === 2; // FightStatus.RESOLVED = 2
        
        let claimable = 0n;
        if (isResolved && !cancelled) {
          // Get claimable without enforce deadline to see total available
          claimable = await booster.quoteClaimable(eventId, fid, userAddress, false);
          
          // Also check with deadline to see if available now
          if (deadline > 0 && now > Number(deadline)) {
            const claimableWithDeadline = await booster.quoteClaimable(eventId, fid, userAddress, true);
            if (claimableWithDeadline === 0n && claimable > 0n) {
              // There's claimable but deadline expired
              claimable = 0n; // Mark as not available
            }
          }
        }
        
        results.push({
          fightId: fid,
          status,
          claimable,
          resolved: isResolved
        });
        
        totalClaimable += claimable;
      } catch (error: any) {
        console.error(`Error getting fight ${fid} information:`, error.message);
      }
    }

    // Show results
    console.log("Results per fight:");
    console.log("─".repeat(80));
    
    for (const result of results) {
      const statusText = result.resolved 
        ? "RESOLVED" 
        : result.status === 0 
          ? "PENDING" 
          : result.status === 1 
            ? "IN_PROGRESS" 
            : "UNKNOWN";
      
      const claimableDisplay = result.claimable > 0n 
        ? `${result.claimable.toString()} FP` 
        : "0 FP";
      
      const fightNum = result.fightId.toString().padStart(2, " ");
      console.log(`Fight ${fightNum}: ${statusText.padEnd(12)} | Claimable: ${claimableDisplay.padStart(15)}`);
    }
    
    console.log("─".repeat(80));
    const totalDisplay = totalClaimable.toString();
    console.log(`Total claimable: ${totalDisplay.padStart(30)} FP`);
    
    if (totalClaimable === 0n) {
      console.log("\n⚠️  Nothing available to claim");
    } else {
      console.log(`\n✓ There are ${totalDisplay} FP available to claim`);
      if (!claimReady) {
        console.log("⚠️  Note: Event is not yet in 'claim ready' state");
      }
      if (deadline > 0 && now > Number(deadline)) {
        console.log("⚠️  Note: Claim deadline has expired");
      }
    }
    
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    process.exit(1);
  }
}

main().catch(console.error);
