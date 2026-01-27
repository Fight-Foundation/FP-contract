import 'dotenv/config';
import { ethers } from 'ethers';

async function main() {
  const eventId = process.argv[2];
  if (!eventId) {
    console.error('Usage: ts-node tools/booster/check-event-fights.ts <eventId>');
    process.exit(1);
  }

  // Determine RPC URL (Mainnet preferred for this task as requested, or explicitly set)
  const rpcUrl = process.env.BSC_RPC_URL || 'https://bsc-dataseed.binance.org';
  
  // Booster Address
  const boosterAddress = process.env.MAINNET_BOOSTER_ADDRESS;
  if (!boosterAddress) {
      console.error('Missing MAINNET_BOOSTER_ADDRESS in .env');
      process.exit(1);
  }

  console.log(`Using RPC: ${rpcUrl}`);
  console.log(`Booster Params:`);
  console.log(`  Address: ${boosterAddress}`);
  console.log(`  EventID: ${eventId}`);

  const provider = new ethers.JsonRpcProvider(rpcUrl);

  const abi = [
      "function getEventFights(string eventId) external view returns (uint256[] fightIds, uint8[] statuses)"
  ];

  const contract = new ethers.Contract(boosterAddress, abi, provider);

  try {
      console.log('Querying getEventFights...');
      const result = await contract.getEventFights(eventId);
      
      const fightIds = result.fightIds;
      const statuses = result.statuses;

      console.log(`\nResult (${fightIds.length} fights):`);
      
      const statusMap = [
          'PENDING', // 0 (Assuming standard enum order, adjusted if needed based on code)
          'OPEN',    // 1
          'IN_PROGRESS', // 2
          'RESOLVED', // 3
          'CANCELLED' // 4 (Just a guess, will print raw integers too)
      ];
      // Note: Without exact enum definition, mapping might be off. Printing raw values is safest.
      
      for (let i = 0; i < fightIds.length; i++) {
          const fid = fightIds[i];
          const st = statuses[i];
          // We'll print raw status. If we knew the Enum, we'd map it.
          console.log(`  Fight ${fid}: Status ${st}`);
      }

  } catch (err: any) {
      console.error('Error querying contract:', err.message || err);
      process.exit(1);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
