// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";

contract GrantMinterToDeployer is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        address deployer = 0xBf797273B60545882711f003094C065351a9CD7B;
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        bytes32 MINTER = token.MINTER_ROLE();
        if (!token.hasRole(MINTER, deployer)) {
            token.grantRole(MINTER, deployer);
            console2.log("Granted MINTER_ROLE to deployer:", deployer);
        } else {
            console2.log("MINTER_ROLE already granted to deployer:", deployer);
        }
        vm.stopBroadcast();
    }
}
