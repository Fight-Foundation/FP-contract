// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FIGHT} from "src/FIGHT.sol";

/**
 * @title DeployFight
 * @notice Foundry script to deploy FIGHT ERC20 token for testing
 * @dev Environment variables:
 *   PRIVATE_KEY         - deployer key
 *   OWNER_ADDRESS       - owner address (optional; defaults to deployer)
 *   TESTNET_RPC_URL     - RPC URL for testnet (use with --rpc-url $TESTNET_RPC_URL)
 * 
 * @dev Usage:
 *   forge script script/DeployFight.s.sol:DeployFight \
 *     --rpc-url $TESTNET_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeployFight is Script {
    // Wallet address to receive 3M tokens
    address constant RECIPIENT_WALLET = 0xF362Fe668d93c43Be16716A73702333795Fbcea6;
    
    // Total supply to mint: 21M tokens
    uint256 constant TOTAL_SUPPLY = 21_000_000 * 1e18;
    
    // Amount to transfer to recipient: 3M tokens
    uint256 constant TRANSFER_AMOUNT = 3_000_000 * 1e18;

    function run() external returns (FIGHT fightToken) {
        address ownerEnv = vm.envOr("OWNER_ADDRESS", address(0));

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address owner = ownerEnv == address(0) ? deployer : ownerEnv;

        console2.log("Deploying FIGHT token with:");
        console2.log("  deployer:", deployer);
        console2.log("  owner:", owner);

        vm.startBroadcast(pk);

        fightToken = new FIGHT(owner);
        console2.log("FIGHT token deployed at:", address(fightToken));
        console2.log("Token name:", fightToken.name());
        console2.log("Token symbol:", fightToken.symbol());

        // Mint 21M tokens to owner
        console2.log("\nMinting 21M tokens to owner...");
        fightToken.mint(owner, TOTAL_SUPPLY);
        console2.log("Minted 21M tokens to:", owner);
        console2.log("Owner balance:", fightToken.balanceOf(owner) / 1e18, "FIGHT");

        // Transfer 3M tokens to recipient wallet
        console2.log("\nTransferring 3M tokens to recipient wallet...");
        fightToken.transfer(RECIPIENT_WALLET, TRANSFER_AMOUNT);
        console2.log("Transferred 3M tokens to:", RECIPIENT_WALLET);
        console2.log("Recipient balance:", fightToken.balanceOf(RECIPIENT_WALLET) / 1e18, "FIGHT");
        console2.log("Owner remaining balance:", fightToken.balanceOf(owner) / 1e18, "FIGHT");

        vm.stopBroadcast();
    }
}

