// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { DailyLottery } from "src/DailyLottery.sol";

/**
 * @title UpgradeDailyLottery
 * @notice Script to upgrade DailyLottery proxy to a new implementation
 * @dev Usage:
 * LOTTERY_ADDRESS=0x5370abf8009a99ab434f87d46b4718165fc7fa5b forge script script/UpgradeDailyLottery.s.sol:UpgradeDailyLottery --rpc-url "https://bsc-testnet.publicnode.com" --broadcast --with-gas-price 3000000000 -vv
 * Verify: 
 *     BSCSCAN_API_KEY=(KEY-VALUE) forge verify-contract 0x9fb696488Bd1Ff578cd5F58D66860e40a300DA20 src/DailyLottery.sol:DailyLottery --chain bsc-testnet
 * Required env vars:
 *   PRIVATE_KEY - Admin private key (must have DEFAULT_ADMIN_ROLE)
 *   PROXY_ADDRESS - Address of the existing proxy to upgrade
 *   BSCSCAN_API_KEY - BscScan API key for contract verification
 */
contract UpgradeDailyLottery is Script {
    function run() external returns (address newImplementation) {
        address proxyAddress = vm.envAddress("LOTTERY_ADDRESS");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        console2.log("Upgrading DailyLottery proxy:");
        console2.log("  proxy:", proxyAddress);
        console2.log("  admin:", admin);

        vm.startBroadcast(pk);

        // Deploy new implementation
        newImplementation = address(new DailyLottery());
        console2.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy to new implementation
        DailyLottery proxy = DailyLottery(proxyAddress);
        proxy.upgradeToAndCall(newImplementation, "");
        console2.log("Proxy upgraded successfully");

        vm.stopBroadcast();
    }
}

