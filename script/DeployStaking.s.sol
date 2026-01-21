// How to deploy:
//
// Testnet (BSC Testnet):
//
// 1. Make sure you have the variables in .env or exported:
//    PRIVATE_KEY=0x...
//    FIGHT_TOKEN_ADDRESS=0x...
//    BSC_TESTNET_RPC_URL=https://bsc-testnet.publicnode.com
//    BSCSCAN_API_KEY=...  # Optional, for verification
//
// 2. Foundry automatically reads variables from .env, but if they're not there:
//    source .env  # Or export manually: export PRIVATE_KEY=0x...
//
// 3. Run the script:
//
//
// With verification (Foundry uses BSCSCAN_API_KEY from foundry.toml if in .env):
//  forge script script/DeployStaking.s.sol:DeployStaking  \
//  --rpc-url "https://bsc-testnet.publicnode.com"  \
//  --broadcast --verify --with-gas-price 20000000000 --priority-gas-price 2000000000 -vv
//
// Note:
// - Foundry automatically reads PRIVATE_KEY and FIGHT_TOKEN_ADDRESS from .env
// - BSCSCAN_API_KEY is read from foundry.toml (which uses ${BSCSCAN_API_KEY} from .env)
// - If BSCSCAN_API_KEY is not defined, omit --verify
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

        // Detect network from RPC URL or use env var
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        string memory network = _detectNetwork(rpcUrl);

        // Display deployment information
        console2.log("");
        console2.log("========================================");
        console2.log("   STAKING CONTRACT DEPLOYMENT");
        console2.log("========================================");
        console2.log("");
        console2.log("Network:", network);
        console2.log("Deployer (Owner):", deployer);
        console2.log("FIGHT Token Address:", fightTokenAddr);
        console2.log("FIGHT Token Code Size:", fightTokenAddr.code.length);
        console2.log("");

        // Request confirmation
        string memory prompt = string.concat("Deploy Staking contract to ", network, "? (y/N): ");
        string memory response = vm.readLine(prompt);

        require(
            keccak256(bytes(response)) == keccak256(bytes("y\n"))
                || keccak256(bytes(response)) == keccak256(bytes("Y\n"))
                || keccak256(bytes(response)) == keccak256(bytes("yes\n"))
                || keccak256(bytes(response)) == keccak256(bytes("YES\n")),
            "Deployment cancelled by user"
        );

        console2.log("");
        console2.log("Deploying...");
        console2.log("");

        vm.startBroadcast(pk);

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

    /**
     * @notice Detect network name from RPC URL
     * @param rpcUrl RPC URL string
     * @return network Network name
     */
    function _detectNetwork(string memory rpcUrl) internal pure returns (string memory) {
        bytes memory urlBytes = bytes(rpcUrl);

        // Check for testnet indicators
        if (_contains(urlBytes, "testnet") || _contains(urlBytes, "bsc-testnet")) {
            return "BSC Testnet";
        }

        // Check for mainnet indicators
        if (_contains(urlBytes, "bsc-dataseed") || _contains(urlBytes, "bsc-mainnet")) {
            return "BSC Mainnet";
        }

        // Default to unknown if can't detect
        if (urlBytes.length > 0) {
            return "Unknown Network";
        }

        return "Local/Anvil";
    }

    /**
     * @notice Check if bytes contain substring
     * @param data Bytes to search in
     * @param search Bytes to search for
     * @return found Whether substring was found
     */
    function _contains(bytes memory data, string memory search) internal pure returns (bool) {
        bytes memory searchBytes = bytes(search);
        if (searchBytes.length > data.length) return false;

        for (uint256 i = 0; i <= data.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                if (data[i + j] != searchBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
