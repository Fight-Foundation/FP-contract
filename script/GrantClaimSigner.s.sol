// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";

contract GrantClaimSigner is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        // Target claim signer address (testnet)
        address claimSigner = 0x3fDDF486b3f539F24aBD845674F18AE33Af668f8;

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        bytes32 ROLE = token.CLAIM_SIGNER_ROLE();
        if (!token.hasRole(ROLE, claimSigner)) {
            token.grantRole(ROLE, claimSigner);
            console2.log("Granted CLAIM_SIGNER_ROLE to:", claimSigner);
        } else {
            console2.log("CLAIM_SIGNER_ROLE already set for:", claimSigner);
        }

        vm.stopBroadcast();
    }
}
