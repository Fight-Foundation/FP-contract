import 'dotenv/config';
import { ethers } from 'ethers';
import fs from 'fs';
import path from 'path';

async function main() {
  const txHash = process.argv[2];
  if (!txHash) {
    console.error('Usage: ts-node tools/check-tx.ts <tx-hash>');
    process.exit(1);
  }

  // Determine RPC URL from env
  const rpcUrl = process.env.RPC_URL || process.env.BSC_TESTNET_RPC_URL || process.env.BSC_RPC_URL;
  if (!rpcUrl) {
    console.error('Missing RPC_URL env var (or BSC_TESTNET_RPC_URL / BSC_RPC_URL)');
    process.exit(1);
  }

  console.log(`Using RPC: ${rpcUrl}`);
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  console.log(`Fetching tx: ${txHash}`);
  let tx;
  try {
    tx = await provider.getTransaction(txHash);
  } catch (err: any) {
    console.error('Error fetching transaction:', err.message);
    process.exit(1);
  }

  if (!tx) {
    console.error('Transaction not found (returned null). It might be incorrect or too old for this node.');
    process.exit(1);
  }

  console.log('Transaction found:');
  console.log(`  To: ${tx.to}`);
  console.log(`  From: ${tx.from}`);
  console.log(`  Value: ${ethers.formatEther(tx.value)} ETH`);
  console.log(`  Data (len): ${tx.data.length}`);

  console.log('Fetching receipt...');
  const receipt = await provider.getTransactionReceipt(txHash);
  if (!receipt) {
    console.log('Transaction is pending (no receipt found).');
    process.exit(0);
  }

  console.log(`Status: ${receipt.status === 1 ? 'SUCCESS' : 'FAILURE'} (${receipt.status})`);
  console.log(`Block: ${receipt.blockNumber}`);
  console.log(`Gas Used: ${receipt.gasUsed.toString()}`);

  if (receipt.logs.length > 0) {
    console.log(`\nLogs (${receipt.logs.length}):`);
    
    // Raw logs only as requested
    for (const log of receipt.logs) {
        console.log(`  Log @ ${log.index}: ${log.address}`);
        console.log(`    Topics:`, log.topics);
        console.log(`    Data:   ${log.data}`);
    }
  } else {
      console.log('No logs emitted.');
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
