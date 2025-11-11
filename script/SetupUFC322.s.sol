// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";

contract SetupUFC322 is Script {
    function run() external {
        address tokenAddr = vm.envAddress("FP1155_ADDRESS");
        address admin = 0xac5d932D7a16D74F713309be227659d387c69429;
        address claimSigner = 0x02D525601e60c2448Abb084e4020926A2Ae5cB01;
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        FP1155 token = FP1155(tokenAddr);
        console2.log("Using token:", tokenAddr);

        // Grant admin roles
        bytes32 DEFAULT_ADMIN = token.DEFAULT_ADMIN_ROLE();
        bytes32 SEASON_ADMIN = token.SEASON_ADMIN_ROLE();
        if (!token.hasRole(DEFAULT_ADMIN, admin)) {
            token.grantRole(DEFAULT_ADMIN, admin);
            console2.log("Granted DEFAULT_ADMIN_ROLE to:", admin);
        }
        if (!token.hasRole(SEASON_ADMIN, admin)) {
            token.grantRole(SEASON_ADMIN, admin);
            console2.log("Granted SEASON_ADMIN_ROLE to:", admin);
        }

        // Open only seasons 0, 321, and 322
        token.setSeasonStatus(0, FP1155.SeasonStatus.OPEN);
        token.setSeasonStatus(321, FP1155.SeasonStatus.OPEN);
        token.setSeasonStatus(322, FP1155.SeasonStatus.OPEN);
        console2.log("Seasons 0, 321, 322 set to OPEN");

        // Grant CLAIM_SIGNER_ROLE
        bytes32 CLAIM_SIGNER = token.CLAIM_SIGNER_ROLE();
        if (!token.hasRole(CLAIM_SIGNER, claimSigner)) {
            token.grantRole(CLAIM_SIGNER, claimSigner);
            console2.log("Granted CLAIM_SIGNER_ROLE to:", claimSigner);
        }

        vm.stopBroadcast();
    }
}
