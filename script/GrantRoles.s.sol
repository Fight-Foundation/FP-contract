// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { FP1155 } from "src/FP1155.sol";

contract GrantRoles is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        address minter = vm.envAddress("TEST_MINT_PUBLIC_KEY");
        address agent = vm.envAddress("TEST_TRANSFER_PUBLIC_KEY");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        console2.log("Using token:", tokenAddr);

        // Grant MINTER_ROLE
        bytes32 minterRole = token.MINTER_ROLE();
        if (!token.hasRole(minterRole, minter)) {
            token.grantRole(minterRole, minter);
            console2.log("Granted MINTER_ROLE to:", minter);
        } else {
            console2.log("MINTER_ROLE already granted:", minter);
        }

        // Grant TRANSFER_AGENT_ROLE
        bytes32 transferAgentRole = token.TRANSFER_AGENT_ROLE();
        if (!token.hasRole(transferAgentRole, agent)) {
            token.grantRole(transferAgentRole, agent);
            console2.log("Granted TRANSFER_AGENT_ROLE to:", agent);
        } else {
            console2.log("TRANSFER_AGENT_ROLE already granted:", agent);
        }

        vm.stopBroadcast();
    }
}
