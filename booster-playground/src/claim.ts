/**
 * Script to claim rewards
 * 
 * Option 1: On behalf of user (use PRIVATE_KEY_USER from .env)
 * npm run claim -- userPk <eventId> [fightId]
 * 
 * Option 2: On behalf of operator (use PRIVATE_KEY from .env)
 * npm run claim -- operatorPk <eventId> [fightId]
 * 
 * Examples:
 * npm run claim -- userPk ufc-323           (claim all available fights)
 * npm run claim -- userPk ufc-323 1         (claim only fight 1)
 * npm run claim -- operatorPk ufc-323       (operator, all fights)
 */
import "dotenv/config";
import { ethers } from "ethers";
import { getBoosterReadOnly, getProvider } from "./booster-client";
import boosterAbi from "./booster-abi.json";

// Minimal ERC1155 ABI for balanceOf
const ERC1155_ABI = [
  "function balanceOf(address account, uint256 id) external view returns (uint256)"
];

async function main() {
  const args = process.argv.slice(2);
  
  // Detect if first argument is "userPk" or "operatorPk"
  let userPk: string | undefined;
  let eventId: string;
  let fightId: string | undefined;

  if (args[0] === "userPk") {
    userPk = process.env.PRIVATE_KEY_USER;
    if (!userPk) {
      console.error("Error: PRIVATE_KEY_USER not found in .env file");
      process.exit(1);
    }
    [, eventId, fightId] = args;
  } else if (args[0] === "operatorPk") {
    userPk = process.env.PRIVATE_KEY_OPERATOR || process.env.OPERATOR_PK || process.env.PRIVATE_KEY;
    if (!userPk) {
      console.error("Error: PRIVATE_KEY_OPERATOR, OPERATOR_PK or PRIVATE_KEY not found in .env file");
      process.exit(1);
    }
    [, eventId, fightId] = args;
  } else {
    console.error("Error: First argument must be 'userPk' or 'operatorPk'");
    console.error("Usage (user mode): npm run claim -- userPk <eventId> [fightId]");
    console.error("Usage (operator mode): npm run claim -- operatorPk <eventId> [fightId]");
    console.error("  eventId: Event ID (e.g: ufc-323)");
    console.error("  fightId: Specific fight ID (optional, if not specified claims all)");
    process.exit(1);
  }
  
  if (!eventId) {
    console.error("Error: Missing eventId");
    console.error("Usage (user mode): npm run claim -- userPk <eventId> [fightId]");
    console.error("Usage (operator mode): npm run claim -- operatorPk <eventId> [fightId]");
    process.exit(1);
  }

  const provider = getProvider();
  const wallet = new ethers.Wallet(
    userPk.startsWith("0x") ? userPk : "0x" + userPk,
    provider
  );
  const userAddress = wallet.address;

  const mode = args[0] === "userPk" ? "user" : "operator";
  console.log(`\n=== Claim for ${mode} ===`);
  console.log(`Address: ${userAddress}`);
  console.log(`Event: ${eventId}\n`);

  const boosterReadOnly = getBoosterReadOnly();
  
  // Create contract with user/operator wallet (don't use getBooster which always uses operator)
  const contractAddress = process.env.TESTNET_BOOSTER_ADDRESS;
  if (!contractAddress) {
    console.error("Error: TESTNET_BOOSTER_ADDRESS not found in .env file");
    process.exit(1);
  }
  const normalizedAddress = ethers.getAddress(contractAddress.trim().replace(/['"]/g, ''));
  const booster = new ethers.Contract(normalizedAddress, boosterAbi, wallet);

  try {
    // Get event information
    const getEventFunc = boosterReadOnly.getFunction("getEvent");
    const [seasonId, numFights, exists, claimReady] = await getEventFunc(eventId);
    
    if (!exists) {
      console.error(`Error: Event ${eventId} does not exist`);
      process.exit(1);
    }

    if (!claimReady) {
      console.error(`Error: Event ${eventId} is not in 'claim ready' state`);
      process.exit(1);
    }

    // Check balance before claim
    const fp1155Address = process.env.TESTNET_FP1155_ADDRESS;
    if (!fp1155Address) {
      console.error("Error: TESTNET_FP1155_ADDRESS not found in .env file");
      process.exit(1);
    }
    
    const fp1155 = new ethers.Contract(
      ethers.getAddress(fp1155Address.trim().replace(/['"]/g, '')),
      ERC1155_ABI,
      provider
    );
    
    const balanceBefore = await fp1155.balanceOf(userAddress, seasonId);
    console.log(`Balance before claim: ${balanceBefore.toString()} FP`);

    // Get fights to claim
    let fightsToClaim: bigint[] = [];
    
    if (fightId) {
      const fightNum = BigInt(fightId);
      if (fightNum < 1 || fightNum > numFights) {
        console.error(`Error: Fight ${fightId} does not exist (valid range: 1-${numFights})`);
        process.exit(1);
      }
      fightsToClaim = [fightNum];
    } else {
      const [fightIds] = await boosterReadOnly.getEventFights(eventId);
      fightsToClaim = fightIds;
    }

    // Get claimable and boost indices for each fight
    const claimInputs: Array<{ fightId: bigint; boostIndices: bigint[] }> = [];
    let totalClaimable = 0n;

    console.log("\nChecking claimable per fight:");
    console.log("─".repeat(80));

    for (const fid of fightsToClaim) {
      try {
        const getFightFunc = boosterReadOnly.getFunction("getFight");
        const fight = await getFightFunc(eventId, fid);
        const status = Number(fight[0]);
        
        if (status !== 2) {
          // Fight not resolved
          continue;
        }

        // Get user boost indices (same as in tests)
        const getUserBoostIndicesFunc = boosterReadOnly.getFunction("getUserBoostIndices");
        const boostIndices = await getUserBoostIndicesFunc(eventId, fid, userAddress);
        
        if (boostIndices.length === 0) {
          continue;
        }

        // Get claimable for this fight
        const quoteClaimableFunc = boosterReadOnly.getFunction("quoteClaimable");
        const claimable = await quoteClaimableFunc(eventId, fid, userAddress, false);
        
        // If there's something claimable, use ALL indices (contract filters automatically)
        // This is what tests do: pass all indices and contract validates
        if (claimable > 0n) {
          // Convert read-only array to normal array
          const indicesArray: bigint[] = [];
          for (let i = 0; i < boostIndices.length; i++) {
            indicesArray.push(BigInt(boostIndices[i].toString()));
          }
          
          claimInputs.push({
            fightId: fid,
            boostIndices: indicesArray
          });
          totalClaimable += claimable;
          console.log(`Fight ${fid.toString().padStart(2, " ")}: ${claimable.toString().padStart(15)} FP (${indicesArray.length} boosts: [${indicesArray.map((i: any) => i.toString()).join(", ")}])`);
        }
      } catch (error: any) {
        // Ignore errors in individual fights
        continue;
      }
    }

    console.log("─".repeat(80));
    console.log(`Total claimable: ${totalClaimable.toString().padStart(30)} FP\n`);

    if (claimInputs.length === 0) {
      console.log("⚠️  Nothing available to claim");
      return;
    }

    // Show details of what will be claimed
    console.log("\nClaim details:");
    for (const input of claimInputs) {
      console.log(`  Fight ${input.fightId}: indices [${input.boostIndices.map(i => i.toString()).join(", ")}]`);
    }

    // Make the claim
    console.log(`\nClaiming ${claimInputs.length} fight(s)...`);
    const tx = await booster.claimRewards(
      eventId,
      claimInputs.map(input => ({
        fightId: input.fightId,
        boostIndices: [...input.boostIndices] // Create copy of array
      }))
    );
    
    console.log("Tx hash:", tx.hash);
    const receipt = await tx.wait();
    console.log(`✓ Claim completed in block ${receipt.blockNumber}`);

    // Check balance after claim
    const balanceAfter = await fp1155.balanceOf(userAddress, seasonId);
    const claimed = balanceAfter - balanceBefore;
    
    console.log(`\nBalance after claim: ${balanceAfter.toString()} FP`);
    console.log(`Claimed: ${claimed.toString()} FP`);
    
    if (claimed > 0n) {
      console.log(`\n✓ Claim successful! Claimed ${claimed.toString()} FP`);
    } else {
      console.log(`\n⚠️  Nothing was claimed (may have already been claimed)`);
    }

  } catch (error: any) {
    console.error("\n❌ Error:", error.message);
    if (error.code) {
      console.error("  Code:", error.code);
    }
    process.exit(1);
  }
}

main().catch(console.error);
