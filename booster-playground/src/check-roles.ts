/**
 * Script to check roles of an address
 * npm run check-roles -- <address>
 * 
 * Example:
 * npm run check-roles -- 0x0c1cd337cb3e57bb5f21161c7c6744e30057db50
 */
import { getBoosterReadOnly } from "./booster-client";
import { ethers } from "ethers";

async function main() {
  const [address] = process.argv.slice(2);
  
  if (!address) {
    console.error("Usage: npm run check-roles -- <address>");
    console.error("  address: Address to check roles for");
    process.exit(1);
  }

  // Validate address format
  if (!address.match(/^0x[a-fA-F0-9]{40}$/)) {
    console.error("Error: Invalid address format");
    process.exit(1);
  }

  const booster = getBoosterReadOnly();
  
  // Get role constants
  const operatorRole = await booster.OPERATOR_ROLE();
  const defaultAdminRole = await booster.DEFAULT_ADMIN_ROLE();
  
  // Check roles
  const hasOperatorRole = await booster.hasRole(operatorRole, address);
  const hasAdminRole = await booster.hasRole(defaultAdminRole, address);
  
  console.log(`\nRoles for address: ${address}`);
  console.log("─".repeat(60));
  console.log(`OPERATOR_ROLE: ${hasOperatorRole ? "✓ YES" : "✗ NO"}`);
  console.log(`  Role ID: ${operatorRole}`);
  console.log(`DEFAULT_ADMIN_ROLE: ${hasAdminRole ? "✓ YES" : "✗ NO"}`);
  console.log(`  Role ID: ${defaultAdminRole}`);
  console.log("─".repeat(60));
  
  if (!hasOperatorRole && !hasAdminRole) {
    console.log("\n⚠️  Address has no roles");
  }
}

main().catch(console.error);






