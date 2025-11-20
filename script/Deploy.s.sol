// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";

/**
 * @title Deploy (Legacy - Non-Upgradeable)
 * @notice This script deploys FP1155 directly without a proxy (LEGACY)
 * @dev For upgradeable deployment, use DeployUpgradeable.s.sol instead
 */
contract Deploy is Script {
    function run() external returns (FP1155 token) {
        string memory baseURI = vm.envOr("BASE_URI", string("ipfs://base/{id}.json"));
        address adminEnv = vm.envOr("ADMIN", address(0));

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        address admin = adminEnv == address(0) ? msg.sender : adminEnv;
        console2.log("Deploying FP1155 with:");
        console2.log("  deployer:", msg.sender);
        console2.log("  admin:", admin);
        console2.log("  baseURI:", baseURI);

        // NOTE: This deploys directly, not through a proxy
        // For upgradeable deployment, use DeployUpgradeable.s.sol
        token = new FP1155();
        token.initialize(baseURI, admin);

        console2.log("FP1155 deployed at:", address(token));
        vm.stopBroadcast();
    }
}
