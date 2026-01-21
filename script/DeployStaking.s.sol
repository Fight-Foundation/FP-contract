// how to deploy:
//
// Testnet (BSC Testnet):
//
// 1. Asegúrate de tener las variables en .env o exportadas:
//    PRIVATE_KEY=0x...
//    FIGHT_TOKEN_ADDRESS=0x...
//    BSC_TESTNET_RPC_URL=https://bsc-testnet.publicnode.com
//    BSCSCAN_API_KEY=...  # Optional, for verification
//
// 2. Foundry lee automáticamente variables de .env, pero si no están:
//    source .env  # O exporta manualmente: export PRIVATE_KEY=0x...
//
// 3. Ejecuta el script:
//
//
// Con verificación (Foundry usa BSCSCAN_API_KEY de foundry.toml si está en .env):
//  forge script script/DeployStaking.s.sol:DeployStaking  \
//  --rpc-url "https://bsc-testnet.publicnode.com"  \
//  --broadcast --verify --with-gas-price 20000000000 --priority-gas-price 2000000000 -vv
//
// Nota:
// - Foundry lee PRIVATE_KEY y FIGHT_TOKEN_ADDRESS desde .env automáticamente
// - BSCSCAN_API_KEY se lee desde foundry.toml (que usa ${BSCSCAN_API_KEY} del .env)
// - Si BSCSCAN_API_KEY no está definida, omite --verify
//
// Mainnet (BSC):
// export BSC_RPC_URL=https://bsc-dataseed.binance.org
// forge script script/DeployStaking.s.sol:DeployStaking \
//   --rpc-url $BSC_RPC_URL \
//   --broadcast \
//   --verify \
//   --etherscan-api-key $BSCSCAN_API_KEY \
//   -vvvv

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Staking } from "src/Staking.sol";

/**
 * @title DeployStaking
 * @notice Foundry script to deploy Staking contract
 * @dev Environment variables:
 *   PRIVATE_KEY         - deployer private key
 *   FIGHT_TOKEN_ADDRESS - address of the FIGHT ERC20 token
 */
contract DeployStaking is Script {
    function run() external returns (Staking staking) {
        address fightTokenAddr = vm.envAddress("FIGHT_TOKEN_ADDRESS");

        // Validate that FIGHT_TOKEN_ADDRESS has code
        require(fightTokenAddr.code.length > 0, "FIGHT_TOKEN_ADDRESS has no code - check deployment");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        console2.log("Deploying Staking contract with:");
        console2.log("  deployer (owner):", deployer);
        console2.log("  fightToken:", fightTokenAddr);
        console2.log("  fightToken code size:", fightTokenAddr.code.length);

        staking = new Staking(fightTokenAddr, deployer);

        console2.log("Staking deployed at:", address(staking));
        console2.log("");

        // Verify contract state
        console2.log("=== Contract State ===");
        console2.log("FIGHT_TOKEN:", address(staking.FIGHT_TOKEN()));
        console2.log("owner:", staking.owner());
        console2.log("paused:", staking.paused());
        console2.log("totalStaked:", staking.totalStaked());

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Summary ===");
        console2.log("Staking contract:", address(staking));
        console2.log("FIGHT Token:", fightTokenAddr);
        console2.log("Owner:", deployer);
    }
}
