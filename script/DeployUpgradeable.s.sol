// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { FP1155 } from "src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployUpgradeable is Script {
    function run() external returns (address proxy, address implementation) {
        string memory baseURI = vm.envOr("BASE_URI", string("ipfs://base/{id}.json"));
        address adminEnv = vm.envOr("ADMIN", address(0));

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address admin = adminEnv == address(0) ? deployer : adminEnv;

        console2.log("Deploying FP1155 (UUPS Upgradeable) with:");
        console2.log("  deployer:", deployer);
        console2.log("  admin:", admin);
        console2.log("  baseURI:", baseURI);

        vm.startBroadcast(pk);

        // Deploy implementation
        implementation = address(new FP1155());
        console2.log("Implementation deployed at:", implementation);

        // Encode initializer call
        bytes memory initData = abi.encodeWithSelector(FP1155.initialize.selector, baseURI, admin);

        // Deploy proxy
        proxy = address(new ERC1967Proxy(implementation, initData));
        console2.log("Proxy deployed at:", proxy);
        console2.log("");
        console2.log("Use proxy address for interactions:", proxy);

        vm.stopBroadcast();
    }
}
