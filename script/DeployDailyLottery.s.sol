// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DailyLottery } from "../src/DailyLottery.sol";
import { FP1155 } from "../src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployDailyLottery
 * @notice Deployment script for DailyLottery contract with UUPS proxy pattern
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:DeployDailyLottery --rpc-url https://bsc-testnet.infura.io/v3/6bb4705a01c54cd9a4715f01b2b73eb6 --broadcast --verify
 */
contract DeployDailyLottery is Script {
    // Environment variables
    address public fpTokenAddress;
    address public lotteryAdmin;

    function setUp() public {
        // Load configuration from environment variables
        fpTokenAddress = vm.envAddress("FP1155_ADDRESS");
        lotteryAdmin = vm.envAddress("LOTTERY_ADMIN_ADDRESS");
        // Note: DEFAULT_ADMIN_ROLE is automatically assigned to deployer (vm.addr(PRIVATE_KEY))
    }

    function run() public {
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address defaultAdmin = vm.addr(deployerPrivateKey); // Deployer gets DEFAULT_ADMIN_ROLE
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying DailyLottery ===");
        console.log("Deployer:", defaultAdmin);
        console.log("FP Token Address:", fpTokenAddress);
        console.log("Default Admin (Deployer):", defaultAdmin);
        console.log("Lottery Admin:", lotteryAdmin);

        // Deploy implementation contract
        DailyLottery implementation = new DailyLottery();
        console.log("Implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(DailyLottery.initialize, (fpTokenAddress, defaultAdmin, lotteryAdmin));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        DailyLottery lottery = DailyLottery(address(proxy));

        // Log deployed addresses
        console.log("\n=== Deployment Summary ===");
        console.log("DailyLottery Implementation:", address(implementation));
        console.log("DailyLottery Proxy:", address(proxy));
        console.log("Current Day ID:", lottery.getCurrentDayId());

        vm.stopBroadcast();

        // Log post-deployment instructions
        console.log("\n=== Post-Deployment Steps ===");
        console.log("1. Grant TRANSFER_AGENT_ROLE to DailyLottery in FP1155:");
        console.log("   FP1155(fpTokenAddress).grantRole(TRANSFER_AGENT_ROLE, lotteryAddress)");
        console.log("   FP Token:", fpTokenAddress);
        console.log("   Lottery:", address(proxy));
        console.log("\n2. Grant FREE_ENTRY_SIGNER_ROLE to backend service:");
        console.log("   DailyLottery(lotteryAddress).grantRole(FREE_ENTRY_SIGNER_ROLE, backend_signer_address)");
        console.log("\n3. Rounds auto-create when users participate (using defaults from initialize)");
        console.log(
            "   To change defaults: DailyLottery.setDefaults(seasonId, entryPrice, maxEntriesPerUser, maxFreeEntriesPerUser)"
        );
        console.log("\n4. To draw winner:");
        console.log("   - For FP: drawWinner(dayId, index, PrizeData(FP, address(0), seasonId, amount))");
        console.log(
            "   - For ERC20: approve token first, then drawWinner(dayId, index, PrizeData(ERC20, tokenAddr, 0, amount))"
        );
    }
}

/**
 * @title SetupDailyLottery
 * @notice Setup script to configure roles after deployment using LOTTERY_ADMIN_ROLE
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:SetupDailyLottery --rpc-url https://bsc-testnet.infura.io/v3/6bb4705a01c54cd9a4715f01b2b73eb6 --broadcast
 * @dev Requires LOTTERY_ADMIN_ADDRESS private key in PRIVATE_KEY env var
 */
contract SetupDailyLottery is Script {
    function run() public {
        // Load addresses
        address lotteryAddress = vm.envAddress("LOTTERY_ADDRESS");
        address fpTokenAddress = vm.envAddress("FP1155_ADDRESS");
        address backendAddress = vm.envAddress("LOTTERY_FREE_ENTRY_SIGNER_ADDRESS");

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        vm.startBroadcast(adminPrivateKey);

        console.log("=== Setting up DailyLottery ===");
        console.log("Lottery Address:", lotteryAddress);
        console.log("Lottery Admin:", admin);
        console.log("FP Token Address:", fpTokenAddress);
        console.log("Free Entry Signer Address:", backendAddress);

        FP1155 fpToken = FP1155(fpTokenAddress);

        // 1. Grant TRANSFER_AGENT_ROLE to lottery in FP1155
        bytes32 transferAgentRole = fpToken.TRANSFER_AGENT_ROLE();
        if (!fpToken.hasRole(transferAgentRole, lotteryAddress)) {
            console.log("\nGranting TRANSFER_AGENT_ROLE to lottery...");
            fpToken.grantRole(transferAgentRole, lotteryAddress);
            console.log("Done");
        } else {
            console.log("\nLottery already has TRANSFER_AGENT_ROLE");
        }

        vm.stopBroadcast();

        console.log("\n=== Setup Complete ===");
    }
}

