// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeFP1155
 * @notice Script to upgrade FP1155 proxy to a new implementation
 * @dev Usage:
 *   forge script script/UpgradeFP1155.s.sol:UpgradeFP1155 \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 * 
 * Required env vars:
 *   PRIVATE_KEY - Admin private key (must have DEFAULT_ADMIN_ROLE)
 *   PROXY_ADDRESS - Address of the existing proxy to upgrade
 */
contract UpgradeFP1155 is Script {
    function run() external returns (address newImplementation) {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        console2.log("Upgrading FP1155 proxy:");
        console2.log("  proxy:", proxyAddress);
        console2.log("  admin:", admin);

        vm.startBroadcast(pk);

        // Deploy new implementation
        newImplementation = address(new FP1155());
        console2.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy to new implementation
        FP1155 proxy = FP1155(proxyAddress);
        proxy.upgradeToAndCall(newImplementation, "");
        console2.log("Proxy upgraded successfully");

        vm.stopBroadcast();
    }
}
