// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";

contract RevokeRoles is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        string memory roleName = vm.envString("ROLE");

        // Optional parameters
        address revokeAccount = vm.envOr("REVOKE_ACCOUNT", address(0));
        address grantAccount = vm.envOr("GRANT_ACCOUNT", address(0));
        bool renounce = vm.envOr("RENOUNCE", false);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        bytes32 role = keccak256(bytes(roleName));

        console2.log("Using token:", tokenAddr);
        console2.logBytes32(role);

        // Revoke
        if (revokeAccount != address(0)) {
            if (token.hasRole(role, revokeAccount)) {
                token.revokeRole(role, revokeAccount);
                console2.log("Revoked role from:", revokeAccount);
            } else {
                console2.log("Skip revoke; account lacks role:", revokeAccount);
            }
        }

        // Grant
        if (grantAccount != address(0)) {
            if (!token.hasRole(role, grantAccount)) {
                token.grantRole(role, grantAccount);
                console2.log("Granted role to:", grantAccount);
            } else {
                console2.log("Skip grant; account already has role:", grantAccount);
            }
        }

        // Renounce
        if (renounce) {
            token.renounceRole(role, msg.sender);
            console2.log("Renounced role for sender:", msg.sender);
        }

        vm.stopBroadcast();
    }
}
