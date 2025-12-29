// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { SimpleStaking } from "src/SimpleStaking.sol";

/**
 * @title DeploySimpleStaking
 * @notice Foundry script to deploy SimpleStaking contract
 * @dev Environment variables:
 *   PRIVATE_KEY         - deployer key
 *   FIGHT_TOKEN_ADDRESS - address of FIGHT token (required)
 *   OWNER_ADDRESS       - owner address (optional; defaults to deployer)
 *   UPDATER_ADDRESS     - updater address for stakeBehalf (optional; defaults to deployer)
 *   START_TIME          - start time for staking in unix timestamp (optional; defaults to now + 1 hour)
 *   TESTNET_RPC_URL     - RPC URL for testnet (use with --rpc-url $TESTNET_RPC_URL)
 *
 * @dev Usage:
 *   forge script script/DeploySimpleStaking.s.sol:DeploySimpleStaking \
 *     --rpc-url $TESTNET_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeploySimpleStaking is Script {
    function run() external returns (SimpleStaking staking) {
        address fightTokenAddr = vm.envAddress("FIGHT_TOKEN_ADDRESS");
        address ownerEnv = vm.envOr("OWNER_ADDRESS", address(0));
        address updaterEnv = vm.envOr("UPDATER_ADDRESS", address(0));

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address owner = ownerEnv == address(0) ? deployer : ownerEnv;
        address updater = updaterEnv == address(0) ? deployer : updaterEnv;

        // Default start time: 1 hour from now, or use env variable
        uint256 startTime = vm.envOr("START_TIME", uint256(block.timestamp + 1 hours));

        console2.log("Deploying SimpleStaking with:");
        console2.log("  deployer:", deployer);
        console2.log("  fightToken:", fightTokenAddr);
        console2.log("  owner:", owner);
        console2.log("  updater:", updater);
        console2.log("  startTime:", startTime);
        console2.log("  startTime (readable):", vm.toString(startTime));

        vm.startBroadcast(pk);

        staking = new SimpleStaking(fightTokenAddr, startTime, owner, updater);
        console2.log("\nSimpleStaking deployed at:", address(staking));
        console2.log("Fight token address:", staking.getFightToken());
        console2.log("Start time:", staking.getStartTime());
        console2.log("Updater:", staking.getUpdater());

        vm.stopBroadcast();
    }
}

