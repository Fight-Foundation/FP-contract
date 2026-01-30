// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Booster } from "src/Booster.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeBooster
 * @notice Script to upgrade Booster proxy to a new implementation
 * @dev Usage:
    forge script script/UpgradeBooster.s.sol:UpgradeBooster \
      --rpc-url https://bsc-testnet.publicnode.com \
      --broadcast \
      --verify \
      --with-gas-price 20000000000 \
      --priority-gas-price 2000000000 \
      -vv
 *
 * Required env vars:
 *   PRIVATE_KEY - Admin private key (must have DEFAULT_ADMIN_ROLE)
 *   PROXY_ADDRESS - Address of the existing proxy to upgrade
 */
contract UpgradeBooster is Script {
    function run() external returns (address newImplementation) {
        address proxyAddress = vm.envAddress("BOOSTER_PROXY_ADDRESS");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        console2.log("Upgrading Booster proxy:");
        console2.log("  proxy:", proxyAddress);
        console2.log("  admin:", admin);

        vm.startBroadcast(pk);

        // Deploy new implementation
        newImplementation = address(new Booster());
        console2.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy to new implementation
        Booster proxy = Booster(proxyAddress);
        proxy.upgradeToAndCall(newImplementation, "");
        console2.log("Proxy upgraded successfully");

        vm.stopBroadcast();
    }
}
