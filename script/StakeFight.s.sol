// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {SimpleStaking} from "src/SimpleStaking.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakeFight
 * @notice Foundry script to stake FIGHT tokens in SimpleStaking contract
 * @dev Environment variables:
 *   USER_PK              - user private key (required)
 *   STAKING_ADDRESS       - address of SimpleStaking contract (required)
 *   STAKE_AMOUNT          - amount to stake in tokens (optional; defaults to 100)
 *   TESTNET_RPC_URL       - RPC URL for testnet (use with --rpc-url $TESTNET_RPC_URL)
 * 
 * @dev Usage:
 *   forge script script/StakeFight.s.sol:StakeFight \
 *     --rpc-url $TESTNET_RPC_URL \
 *     --broadcast \
 *     -vvvv
 */
contract StakeFight is Script {
    // Amount to stake: 100 tokens (100 * 1e18)
    uint256 constant DEFAULT_STAKE_AMOUNT = 100 * 1e18;

    function run() external {
        uint256 userPk = vm.envUint("USER_PK");
        address stakingAddr = vm.envAddress("STAKING_ADDRESS");
        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", DEFAULT_STAKE_AMOUNT);
        
        address user = vm.addr(userPk);
        SimpleStaking staking = SimpleStaking(stakingAddr);
        address fightTokenAddr = staking.getFightToken();
        IERC20 fightToken = IERC20(fightTokenAddr);

        console2.log("Staking FIGHT tokens:");
        console2.log("  user:", user);
        console2.log("  staking contract:", stakingAddr);
        console2.log("  fight token:", fightTokenAddr);
        console2.log("  stake amount:", stakeAmount / 1e18, "FIGHT");

        // Check user balance
        uint256 userBalance = fightToken.balanceOf(user);
        console2.log("  user balance:", userBalance / 1e18, "FIGHT");
        require(userBalance >= stakeAmount, "Insufficient balance");

        // Check current allowance
        uint256 currentAllowance = fightToken.allowance(user, stakingAddr);
        console2.log("  current allowance:", currentAllowance / 1e18, "FIGHT");

        vm.startBroadcast(userPk);

        // Approve if needed
        if (currentAllowance < stakeAmount) {
            console2.log("\nApproving tokens...");
            fightToken.approve(stakingAddr, stakeAmount);
            console2.log("Approved", stakeAmount / 1e18, "FIGHT");
        }

        // Get user data before stake
        SimpleStaking.Data memory userDataBefore = staking.getUser(user);
        console2.log("\nUser data before stake:");
        console2.log("  staked amount:", userDataBefore.amount / 1e18, "FIGHT");
        console2.log("  cumulative weight:", userDataBefore.cumulativeWeight);

        // Stake tokens
        console2.log("\nStaking tokens...");
        staking.stake(stakeAmount);
        console2.log("Staked", stakeAmount / 1e18, "FIGHT successfully!");

        // Get user data after stake
        SimpleStaking.Data memory userDataAfter = staking.getUser(user);
        console2.log("\nUser data after stake:");
        console2.log("  staked amount:", userDataAfter.amount / 1e18, "FIGHT");
        console2.log("  cumulative weight:", userDataAfter.cumulativeWeight);

        // Get pool info
        uint256 totalStaked = staking.getTotalStaked();
        console2.log("\nPool info:");
        console2.log("  total staked:", totalStaked / 1e18, "FIGHT");

        vm.stopBroadcast();
    }
}




