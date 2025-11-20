// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { FP1155 } from "src/FP1155.sol";

contract MintToAdmin is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        address admin = 0xac5d932D7a16D74F713309be227659d387c69429;
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        console2.log("Minting 1 token for each open season to:", admin);
        token.mint(admin, 0, 1, "");
        token.mint(admin, 321, 1, "");
        token.mint(admin, 322, 1, "");
        vm.stopBroadcast();
    }
}
