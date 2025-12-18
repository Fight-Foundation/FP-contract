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
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:DeployDailyLottery --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployDailyLottery is Script {
    // Environment variables
    address public fpTokenAddress;
    address public admin;

    function setUp() public {
        // Load configuration from environment variables
        fpTokenAddress = vm.envAddress("FP_TOKEN_ADDRESS");
        admin = vm.envAddress("ADMIN_ADDRESS");
    }

    function run() public {
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying DailyLottery ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("FP Token Address:", fpTokenAddress);
        console.log("Admin Address:", admin);

        // Deploy implementation contract
        DailyLottery implementation = new DailyLottery();
        console.log("Implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            DailyLottery.initialize,
            (fpTokenAddress, admin)
        );

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
        console.log("   To change defaults: DailyLottery.setDefaults(seasonId, entryPrice, maxEntriesPerUser)");
        console.log("\n4. To draw winner:");
        console.log("   - For FP: drawWinner(dayId, index, PrizeData(FP, address(0), seasonId, amount))");
        console.log("   - For ERC20: approve token first, then drawWinner(dayId, index, PrizeData(ERC20, tokenAddr, 0, amount))");
    }
}

/**
 * @title SetupDailyLottery
 * @notice Setup script to configure roles and initial prize pool after deployment
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:SetupDailyLottery --rpc-url <RPC_URL> --broadcast
 */
contract SetupDailyLottery is Script {
    function run() public {
        // Load addresses
        address lotteryAddress = vm.envAddress("LOTTERY_ADDRESS");
        address fpTokenAddress = vm.envAddress("FP_TOKEN_ADDRESS");
        address backendAddress = vm.envAddress("BACKEND_ADDRESS");
        uint256 fpPrizeAmount = vm.envUint("FP_PRIZE_AMOUNT");
        uint256 usdtPrizeAmount = vm.envUint("USDT_PRIZE_AMOUNT");

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        vm.startBroadcast(adminPrivateKey);

        console.log("=== Setting up DailyLottery ===");
        console.log("Lottery Address:", lotteryAddress);
        console.log("Admin:", admin);

        DailyLottery lottery = DailyLottery(lotteryAddress);
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

        // 2. Grant FREE_ENTRY_SIGNER_ROLE to backend
        bytes32 freeEntrySignerRole = lottery.FREE_ENTRY_SIGNER_ROLE();
        if (!lottery.hasRole(freeEntrySignerRole, backendAddress)) {
            console.log("\nGranting FREE_ENTRY_SIGNER_ROLE to backend...");
            lottery.grantRole(freeEntrySignerRole, backendAddress);
            console.log("Done");
        } else {
            console.log("\nBackend already has FREE_ENTRY_SIGNER_ROLE");
        }

        // 3. Set approvals for future lottery rounds
        console.log("\nSetting approvals for FP token...");
        fpToken.setApprovalForAll(lotteryAddress, true);
        console.log("FP token approval set");
        
        console.log("\nNote: Admin must approve each ERC20 prize token before drawing winners");
        console.log("Example: IERC20(prizeTokenAddress).approve(lotteryAddress, amount)");

        vm.stopBroadcast();

        console.log("\n=== Setup Complete ===");
    }
}

/**
 * @title SetDailyLotteryDefaults
 * @notice Script to set default values for auto-created lottery rounds
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:SetDailyLotteryDefaults --rpc-url <RPC_URL> --broadcast
 */
contract SetDailyLotteryDefaults is Script {
    function run() public {
        address lotteryAddress = vm.envAddress("LOTTERY_ADDRESS");
        uint256 seasonId = vm.envUint("SEASON_ID");
        uint256 entryPrice = vm.envOr("ENTRY_PRICE", uint256(1));
        uint256 maxEntriesPerUser = vm.envOr("MAX_ENTRIES_PER_USER", uint256(5));

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(adminPrivateKey);

        console.log("=== Setting Lottery Defaults ===");
        console.log("Lottery Address:", lotteryAddress);
        console.log("Default Season ID:", seasonId);
        console.log("Default Entry Price:", entryPrice);
        console.log("Default Max Entries Per User:", maxEntriesPerUser);

        DailyLottery lottery = DailyLottery(lotteryAddress);
        lottery.setDefaults(seasonId, entryPrice, maxEntriesPerUser);

        console.log("\n=== Defaults Updated ===");
        console.log("New rounds will auto-create with these values when users participate");

        vm.stopBroadcast();
    }
}

/**
 * @title DrawDailyLotteryWinner
 * @notice Script to draw the winner for a lottery round using off-chain randomness
 * @dev Usage: forge script script/DeployDailyLottery.s.sol:DrawDailyLotteryWinner --rpc-url <RPC_URL> --broadcast
 * 
 * The winning index should be generated off-chain using a secure random number generator.
 * Example in Python:
 *   import secrets
 *   total_entries = 100
 *   winning_index = secrets.randbelow(total_entries)
 * 
 * Example in JavaScript:
 *   const totalEntries = 100;
 *   const winningIndex = Math.floor(Math.random() * totalEntries);
 */
contract DrawDailyLotteryWinner is Script {
    function run() public {
        address lotteryAddress = vm.envAddress("LOTTERY_ADDRESS");
        uint256 dayId = vm.envUint("DAY_ID");
        uint256 winningIndex = vm.envUint("WINNING_INDEX");

        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(adminPrivateKey);

        console.log("=== Drawing Lottery Winner ===");
        console.log("Lottery Address:", lotteryAddress);
        console.log("Day ID:", dayId);
        console.log("Winning Index:", winningIndex);

        DailyLottery lottery = DailyLottery(lotteryAddress);
        
        DailyLottery.LotteryRound memory roundBefore = lottery.getLotteryRound(dayId);
        console.log("\nTotal Entries:", roundBefore.totalEntries);
        
        require(winningIndex < roundBefore.totalEntries, "Invalid winning index");

        uint256 prizeType = vm.envUint("PRIZE_TYPE");
        address prizeTokenAddress = vm.envOr("PRIZE_TOKEN_ADDRESS", address(0)); // For ERC20 prizes
        uint256 seasonId = vm.envOr("SEASON_ID", uint256(0)); // For FP prizes
        uint256 prizeAmount = vm.envUint("PRIZE_AMOUNT");
        
        DailyLottery.PrizeType prizeTypeEnum = prizeType == 0 
            ? DailyLottery.PrizeType.FP 
            : DailyLottery.PrizeType.ERC20;

        console.log("Prize Type:", prizeType == 0 ? "FP" : "ERC20");
        if (prizeType == 0) {
            console.log("Season ID:", seasonId);
        } else {
            console.log("Prize Token Address:", prizeTokenAddress);
        }
        console.log("Prize Amount:", prizeAmount);

        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: prizeTypeEnum,
            tokenAddress: prizeTokenAddress,
            seasonId: seasonId,
            amount: prizeAmount
        });

        lottery.drawWinner(dayId, winningIndex, prize);

        DailyLottery.LotteryRound memory roundAfter = lottery.getLotteryRound(dayId);

        console.log("\n=== Winner Drawn ===");
        console.log("Winner:", roundAfter.winner);
        console.log("Finalized:", roundAfter.finalized);

        vm.stopBroadcast();
    }
}

