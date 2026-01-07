import 'dotenv/config';
import { ethers } from 'ethers';

type Profile = 'deploy' | 'sign-claim' | 'submit-claim' | 'verify';

function usage(): never {
  console.error('Usage: ts-node tools/validate-env.ts <deploy|sign-claim|submit-claim|verify>');
  process.exit(2);
}

function requireVar(name: string, altNames: string[] = []) {
  const keys = [name, ...altNames];
  for (const k of keys) {
    const v = process.env[k];
    if (v && v.trim().length > 0) return { key: k, value: v.trim() };
  }
  const label = altNames.length ? `${name} (or ${altNames.join(' / ')})` : name;
  throw new Error(`Missing required env: ${label}`);
}

function optionalVar(name: string) {
  const v = process.env[name];
  return v && v.trim().length > 0 ? v.trim() : undefined;
}

function assertHexPrivateKey(name: string, value: string) {
  const hex = value.startsWith('0x') ? value.slice(2) : value;
  if (!/^([0-9a-fA-F]{64})$/.test(hex)) throw new Error(`${name} must be a 32-byte hex private key`);
}

function assertAddress(name: string, value: string) {
  try { ethers.getAddress(value); } catch { throw new Error(`${name} must be a valid address`); }
}

function checkRpc() {
  // Accept RPC_URL or TESTNET_BSC_RPC_URL or BSC_RPC_URL
  const rpc = requireVar('RPC_URL', ['TESTNET_BSC_RPC_URL', 'BSC_RPC_URL']);
  console.log(`RPC ok: ${rpc.key}`);
}

function checkDeploy() {
  checkRpc();
  const pk = requireVar('PRIVATE_KEY');
  assertHexPrivateKey(pk.key, pk.value);
  console.log('PRIVATE_KEY ok');
  const admin = optionalVar('ADMIN');
  if (admin) { assertAddress('ADMIN', admin); console.log('ADMIN ok'); }
  const base = optionalVar('BASE_URI');
  if (base) console.log('BASE_URI ok');
}

function checkSignClaim() {
  checkRpc();
  const pk = requireVar('CLAIM_SIGNER_PK', ['PRIVATE_KEY']);
  assertHexPrivateKey(pk.key, pk.value);
  console.log(`${pk.key} ok`);
  const addr = optionalVar('FP1155_ADDRESS');
  if (addr) { assertAddress('FP1155_ADDRESS', addr); console.log('FP1155_ADDRESS ok'); }
}

function checkSubmitClaim() {
  checkRpc();
  const pk = requireVar('USER_PK', ['PRIVATE_KEY']);
  assertHexPrivateKey(pk.key, pk.value);
  console.log(`${pk.key} ok`);
  const addr = requireVar('FP1155_ADDRESS');
  assertAddress(addr.key, addr.value);
  console.log('FP1155_ADDRESS ok');
}

function checkVerify() {
  const key = requireVar('BSCSCAN_API_KEY');
  if (key.value.length < 10) throw new Error('BSCSCAN_API_KEY looks too short');
  console.log('BSCSCAN_API_KEY ok');
}

async function main() {
  const profile = (process.argv[2] ?? '').trim() as Profile;
  if (!profile || !['deploy', 'sign-claim', 'submit-claim', 'verify'].includes(profile)) usage();
  try {
    if (profile === 'deploy') checkDeploy();
    else if (profile === 'sign-claim') checkSignClaim();
    else if (profile === 'submit-claim') checkSubmitClaim();
    else if (profile === 'verify') checkVerify();
    console.log(`Validation for '${profile}' succeeded.`);
  } catch (err: any) {
    console.error(`Validation for '${profile}' failed:`, err.message ?? err);
    process.exit(1);
  }
}

main();
