// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";
import {Booster} from "src/Booster.sol";

/**
 * @title DeployBooster
 * @notice Foundry script to deploy Booster and wire required FP1155 roles.
 * @dev Environment variables:
 *   PRIVATE_KEY           - deployer key
 *   FP1155_ADDRESS        - existing FP1155 contract address
 *   OPERATOR_ADDRESS      - address to be granted OPERATOR_ROLE (optional; defaults to deployer)
 *   ALLOWLIST_USERS       - comma-separated addresses to allowlist (optional)
 *   BASE_DEADLINE_OFFSET  - seconds offset from now for initial claim deadline (optional, 0 = none)
 */
contract DeployBooster is Script {
    function run() external returns (Booster booster) {
        address fpAddr = vm.envAddress("FP1155_ADDRESS");
        address operatorEnv = vm.envOr("OPERATOR_ADDRESS", address(0));
        uint256 deadlineOffset = vm.envOr("BASE_DEADLINE_OFFSET", uint256(0));

        uint256 pk = vm.envUint("PRIVATE_KEY");
        // The account derived from PRIVATE_KEY; use this explicitly for admin
        address admin = vm.addr(pk);
        vm.startBroadcast(pk);

        // Operator falls back to admin if not provided
        address operator = operatorEnv == address(0) ? admin : operatorEnv;

        FP1155 fp = FP1155(fpAddr);
        console2.log("Using FP1155:", fpAddr);
        console2.log("Admin:", admin);
        console2.log("Operator:", operator);

        // Deploy booster with admin as DEFAULT_ADMIN_ROLE holder
        booster = new Booster(fpAddr, admin);
        console2.log("Booster deployed at:", address(booster));

        // Grant Booster TRANSFER_AGENT_ROLE on FP1155 so it can move FP.
        bytes32 transferAgentRole = fp.TRANSFER_AGENT_ROLE();
        if (!fp.hasRole(transferAgentRole, address(booster))) {
            fp.grantRole(transferAgentRole, address(booster));
            console2.log("Granted TRANSFER_AGENT_ROLE to Booster");
        }

        // Allowlist Booster endpoints: operator and any provided users.
        fp.setTransferAllowlist(address(booster), true); // Not strictly required but harmless.
        fp.setTransferAllowlist(operator, true);

        // Grant OPERATOR_ROLE on Booster to operator
        bytes32 opRole = booster.OPERATOR_ROLE();
        if (!booster.hasRole(opRole, operator)) {
            booster.grantRole(opRole, operator);
            console2.log("Granted OPERATOR_ROLE to:", operator);
        }

        // Optional additional allowlist addresses
        {
            string memory raw = vm.envOr("ALLOWLIST_USERS", string(""));
            if (bytes(raw).length > 0) {
                // Simple parsing: split by comma
                uint256 count = 1;
                for (uint256 i = 0; i < bytes(raw).length; i++) {
                    if (bytes(raw)[i] == ",") count++;
                }
                address[] memory addrs = new address[](count);
                uint256 idx = 0;
                uint256 start = 0;
                for (uint256 i = 0; i <= bytes(raw).length; i++) {
                    if (i == bytes(raw).length || bytes(raw)[i] == ",") {
                        bytes memory slice = new bytes(i - start);
                        for (uint256 j = start; j < i; j++) {
                            slice[j - start] = bytes(raw)[j];
                        }
                        addrs[idx] = vm.parseAddress(string(slice));
                        idx++;
                        start = i + 1;
                    }
                }
                for (uint256 k = 0; k < addrs.length; k++) {
                    fp.setTransferAllowlist(addrs[k], true);
                    console2.log("Allowlisted user:", addrs[k]);
                }
            }
        }

        // Optionally set a global claim deadline for an event after creation (not created here).
        if (deadlineOffset > 0) {
            console2.log(
                "NOTE: deadlineOffset provided but no event created in this script. Use a separate script to create events and set deadlines."
            );
        }

        vm.stopBroadcast();
    }
}
