// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {FP1155} from "src/FP1155.sol";
import {Sportsbook} from "src/Sportsbook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeploySportsbook is Script {
    function run() external {
        // ============ STEP 1: Load environment variables ============
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("ADMIN", address(0));
        address fp1155Address = vm.envAddress("FP1155_ADDRESS");
        
        // If admin not set, use deployer
        if (admin == address(0)) {
            admin = vm.addr(deployerPrivateKey);
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        console2.log("=== DEPLOYING SPORTSBOOK ===");
        console2.log("Deployer:", vm.addr(deployerPrivateKey));
        console2.log("Admin:", admin);
        console2.log("FP1155 Address:", fp1155Address);
        
        // ============ STEP 2: Use existing FP1155 ============
        require(fp1155Address != address(0), "FP1155_ADDRESS must be set in .env");
        
        console2.log("\nUsing existing FP1155 at:", fp1155Address);
        FP1155 fp1155 = FP1155(fp1155Address);
        
        // ============ STEP 3: Deploy Sportsbook Implementation ============
        console2.log("\nDeploying Sportsbook implementation...");
        Sportsbook sportsbookImpl = new Sportsbook();
        console2.log("Sportsbook implementation deployed at:", address(sportsbookImpl));
        
        // ============ STEP 4: Encode initialize call ============
        bytes memory initData = abi.encodeWithSelector(
            Sportsbook.initialize.selector,
            address(fp1155),
            admin
        );
        
        // ============ STEP 5: Deploy ERC1967Proxy ============
        console2.log("\nDeploying ERC1967Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(sportsbookImpl), initData);
        Sportsbook sportsbook = Sportsbook(payable(address(proxy)));
        console2.log("ERC1967Proxy deployed at:", address(proxy));
        console2.log("Sportsbook (proxy) address:", address(sportsbook));
        
        // ============ STEP 6: Configuration Note ============
        // Note: FP1155 configuration (granting TRANSFER_AGENT_ROLE and adding to allowlist)
        // should be done separately from the FP1155 contract by an admin
        
        vm.stopBroadcast();
        
        // ============ STEP 7: Summary ============
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("FP1155 address:", address(fp1155));
        console2.log("Sportsbook implementation:", address(sportsbookImpl));
        console2.log("Sportsbook proxy:", address(sportsbook));
        console2.log("Admin:", admin);
        console2.log("\n=== NEXT STEPS ===");
        console2.log("1. Verify contracts on block explorer");
        console2.log("2. Configure FP1155 (from FP1155 contract):");
        console2.log("   - Grant TRANSFER_AGENT_ROLE to Sportsbook:", address(sportsbook));
        console2.log("   - Add Sportsbook to allowlist:", address(sportsbook));
        console2.log("3. Grant additional roles if needed");
        console2.log("4. Create first season using createSeasonWithFights()");
    }
}

