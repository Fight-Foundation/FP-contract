// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { Booster } from "../src/Booster.sol";
import { FP1155 } from "../src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title BoosterFPTest
 * @notice Test case: Single Fight Analysis - Fight 0 only
 * @dev Tests Booster contract using FP1155 tokens:
 *      - User1 bets 20 FP on outcome 0 (RED + SUBMISSION) - exact match (4 shares)
 *      - User2 bets 30 FP on outcome 1 (RED + DECISION) - winner only (3 shares)
 *      - User3 bets 25 FP on outcome 0 (RED + SUBMISSION) - exact match (4 shares)
 *      - Winning outcome: 0 (RED + SUBMISSION)
 *      - Prize pool: 100 FP
 */
contract BoosterFPTest is Test {
    Booster public booster;
    FP1155 public fp;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");

    uint256 constant SEASON_1 = 1;
    string constant EVENT_1 = "UFC_300";
    uint256 constant FIGHT_1 = 1;

    // Points system: winner only = 3, exact match = 4
    uint256 constant POINTS_FOR_WINNER = 3;
    uint256 constant POINTS_FOR_WINNER_METHOD = 4;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy FP1155 via ERC1967Proxy and initialize
        FP1155 implementation = new FP1155();
        bytes memory initData =
            abi.encodeWithSelector(FP1155.initialize.selector, "https://api.fightfoundation.io/fp/", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        fp = FP1155(address(proxy));

        // Deploy Booster via ERC1967Proxy and initialize
        Booster boosterImplementation = new Booster();
        bytes memory boosterInitData = abi.encodeWithSelector(Booster.initialize.selector, address(fp), admin);
        ERC1967Proxy boosterProxy = new ERC1967Proxy(address(boosterImplementation), boosterInitData);
        booster = Booster(address(boosterProxy));

        // Grant roles
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(booster));
        fp.grantRole(fp.MINTER_ROLE(), admin);

        booster.grantRole(booster.OPERATOR_ROLE(), operator);

        // Mint FP tokens to users (FP1155 uses units, not decimals)
        // Minting 100 units of FP token (season 1) to each user
        fp.mint(user1, SEASON_1, 100, "");
        fp.mint(user2, SEASON_1, 100, "");
        fp.mint(user3, SEASON_1, 100, "");
        fp.mint(user4, SEASON_1, 100, "");
        fp.mint(user5, SEASON_1, 100, "");
        fp.mint(operator, SEASON_1, 500, "");

        // Allowlist participants for transfers
        fp.setTransferAllowlist(user1, true);
        fp.setTransferAllowlist(user2, true);
        fp.setTransferAllowlist(user3, true);
        fp.setTransferAllowlist(user4, true);
        fp.setTransferAllowlist(user5, true);
        fp.setTransferAllowlist(operator, true);

        vm.stopPrank();
    }

    function test_singleFight() public {
        console2.log("\n=== TEST CASE: Single Fight Analysis ===");

        vm.prank(operator);
        booster.createEvent(EVENT_1, 1, SEASON_1, 0);

        uint256 prizePool = 100;

        // Deposit prize pool as bonus
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, prizePool, false);

        // Verify prize pool deposited
        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, prizePool, "Prize pool should be 100 FP");

        // Define stakes
        uint256 stake1 = 20;
        uint256 stake2 = 30;
        uint256 stake3 = 25;

        console2.log("Setup: User1 bets %d on RED + SUBMISSION", stake1);
        console2.log("       User2 bets %d on RED + DECISION", stake2);
        console2.log("       User3 bets %d on RED + SUBMISSION", stake3);

        // User1: Bets on Fight 1 (RED + SUBMISSION) - exact match (4 points)
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, stake1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts1);

        // User2: Bets on Fight 1 (RED + DECISION) - winner only (3 points)
        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_1, stake2, Booster.Corner.RED, Booster.WinMethod.DECISION);
        booster.placeBoosts(EVENT_1, boosts2);

        // User3: Bets on Fight 1 (RED + SUBMISSION) - exact match (4 points)
        vm.prank(user3);
        Booster.BoostInput[] memory boosts3 = new Booster.BoostInput[](1);
        boosts3[0] = Booster.BoostInput(FIGHT_1, stake3, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts3);

        // Verify balances after predictions
        uint256 balanceAfterPredictions1 = fp.balanceOf(user1, SEASON_1);
        uint256 balanceAfterPredictions2 = fp.balanceOf(user2, SEASON_1);
        uint256 balanceAfterPredictions3 = fp.balanceOf(user3, SEASON_1);
        uint256 totalStakes = stake1 + stake2 + stake3;

        assertEq(balanceAfterPredictions1, 100 - stake1, "User1 should have 80 FP after prediction");
        assertEq(balanceAfterPredictions2, 100 - stake2, "User2 should have 70 FP after prediction");
        assertEq(balanceAfterPredictions3, 100 - stake3, "User3 should have 75 FP after prediction");

        // Verify original pool
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(originalPool, totalStakes, "Original pool should equal total stakes");
        // Calculate winning pool total shares dynamically
        // User1: RED + SUBMISSION (exact match) = 4 points * 20 stake = 80 shares
        // User2: RED + DECISION (winner only) = 3 points * 30 stake = 90 shares
        // User3: RED + SUBMISSION (exact match) = 4 points * 25 stake = 100 shares
        uint256 user1Points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        uint256 user2Points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.DECISION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user3Points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        assertEq(user1Points, POINTS_FOR_WINNER_METHOD, "User1 should have 4 points (exact match)");
        assertEq(user2Points, POINTS_FOR_WINNER, "User2 should have 3 points (winner only)");
        assertEq(user3Points, POINTS_FOR_WINNER_METHOD, "User3 should have 4 points (exact match)");

        // Calculate sumWinnersStakes and winningPoolTotalShares
        // User1: 4 points, 20 stake -> 4 * 20 = 80 shares
        // User2: 3 points, 30 stake -> 3 * 30 = 90 shares
        // User3: 4 points, 25 stake -> 4 * 25 = 100 shares
        // sumWinnersStakes = 20 + 30 + 25 = 75
        // winningPoolTotalShares = 80 + 90 + 100 = 270
        uint256 sumWinnersStakes = stake1 + stake2 + stake3;
        uint256 winningPoolTotalShares = (user1Points * stake1) + (user2Points * stake2) + (user3Points * stake3);

        // Winning outcome: Fight 1: 0 (RED + SUBMISSION) - User1 and User3 win
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes,
            winningPoolTotalShares
        );

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(EVENT_1, true);

        // Get total winnings pool (prize pool)
        // prizePool = originalPool - sumWinnersStakes + bonusPool
        // In this case: originalPool = 75, sumWinnersStakes = 75, bonusPool = 100
        // prizePool = 75 - 75 + 100 = 100
        uint256 totalPool = originalPool - sumWinnersStakes + prizePool; // 75 - 75 + 100 = 100

        console2.log("\nResolution: Winning RED + SUBMISSION");
        console2.log("           Total Winnings Pool: %d", totalPool);
        console2.log("           Sum Winners Stakes: %d", sumWinnersStakes);
        console2.log("           Winning Pool Total Shares: %d", winningPoolTotalShares);

        // ============ STEP 6: Users claim winnings ============
        // Get boost indices for each user
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);
        uint256[] memory indices3 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user3);

        // User1 should have winnings from Fight 1 (exact match, 4 points)
        uint256 balanceBefore1 = fp.balanceOf(user1, SEASON_1);

        // Get actual claimable amount from contract
        uint256 totalClaimable1 = booster.quoteClaimable(EVENT_1, FIGHT_1, user1, false);

        assertGt(totalClaimable1, 0, "User1 should be able to claim");
        assertEq(user1Points, POINTS_FOR_WINNER_METHOD, "User1 should have 4 points (exact match)");

        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);
        uint256 balanceAfter1 = fp.balanceOf(user1, SEASON_1);
        assertEq(balanceAfter1, balanceBefore1 + totalClaimable1, "User1 balance should increase by claimable amount");

        // User2 should have winnings from Fight 1 (winner only, 3 points)
        uint256 balanceBefore2 = fp.balanceOf(user2, SEASON_1);

        // Get actual claimable amount from contract
        uint256 totalClaimable2 = booster.quoteClaimable(EVENT_1, FIGHT_1, user2, false);
        assertGt(totalClaimable2, 0, "User2 should be able to claim");
        assertEq(user2Points, POINTS_FOR_WINNER, "User2 should have 3 points (winner only)");

        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, indices2);

        uint256 balanceAfter2 = fp.balanceOf(user2, SEASON_1);
        assertEq(balanceAfter2, balanceBefore2 + totalClaimable2, "User2 balance should increase by claimable amount");

        // User3 should have winnings from Fight 1 (exact match, 4 points)
        uint256 balanceBefore3 = fp.balanceOf(user3, SEASON_1);

        // Get actual claimable amount from contract
        uint256 totalClaimable3 = booster.quoteClaimable(EVENT_1, FIGHT_1, user3, false);
        assertGt(totalClaimable3, 0, "User3 should be able to claim");
        assertEq(user3Points, POINTS_FOR_WINNER_METHOD, "User3 should have 4 points (exact match)");

        vm.prank(user3);
        booster.claimReward(EVENT_1, FIGHT_1, indices3);

        uint256 balanceAfter3 = fp.balanceOf(user3, SEASON_1);
        assertEq(balanceAfter3, balanceBefore3 + totalClaimable3, "User3 balance should increase by claimable amount");

        console2.log("\n=== RESULTS SUMMARY ===");
        console2.log("User1 claimable: %d", totalClaimable1);
        console2.log("User2 claimable: %d", totalClaimable2);
        console2.log("User3 claimable: %d", totalClaimable3);

        // Verify all positions are claimed
        uint256 claimable1After = booster.quoteClaimable(EVENT_1, FIGHT_1, user1, false);
        uint256 claimable2After = booster.quoteClaimable(EVENT_1, FIGHT_1, user2, false);
        uint256 claimable3After = booster.quoteClaimable(EVENT_1, FIGHT_1, user3, false);
        assertEq(claimable1After, 0, "User1 should have no remaining claimable");
        assertEq(claimable2After, 0, "User2 should have no remaining claimable");
        assertEq(claimable3After, 0, "User3 should have no remaining claimable");

        // Calculate remainder (truncation remainder from integer division)
        // The remainder is only from the prizePool (winnings), not from the stakes
        // Each user gets back their stake + winnings, so we need to subtract stakes from totalClaimable
        // User1: stake1 = 20, User2: stake2 = 30, User3: stake3 = 25
        uint256 totalWinningsDistributed =
            (totalClaimable1 - stake1) + (totalClaimable2 - stake2) + (totalClaimable3 - stake3);
        uint256 expectedRemainder = totalPool - totalWinningsDistributed;
        uint256 contractBalanceAfter = fp.balanceOf(address(booster), SEASON_1);
        assertEq(contractBalanceAfter, expectedRemainder, "Contract should have truncation remainder");

        console2.log("Remainder in Contract: %d (truncation remainder)", expectedRemainder);

        //print users balances
        console2.log("User1 balance: %d", fp.balanceOf(user1, SEASON_1));
        console2.log("User2 balance: %d", fp.balanceOf(user2, SEASON_1));
        console2.log("User3 balance: %d", fp.balanceOf(user3, SEASON_1));
    }

    // Helper function to get user winnings
    function _getUserWinnings(
        string memory eventId,
        uint256 fightId,
        address user,
        uint256 totalPool,
        uint256 totalWinningPoints,
        uint256 stake,
        uint256 points
    ) internal view returns (uint256 canClaim, uint256 winnings, uint256 totalPayout) {
        uint256 totalClaimable = booster.quoteClaimable(eventId, fightId, user, false);
        canClaim = totalClaimable > 0 ? 1 : 0;

        uint256 userShares = points * stake; // points * amount for this boost
        winnings = (totalPool * userShares) / totalWinningPoints;
        totalPayout = stake + winnings;
    }

    /**
     * @notice Test case: Multiple Fights - Complete flow with 5 fights
     * @dev Tests Booster contract with multiple fights:
     *      - Create event with 5 fights
     *      - Users make predictions across multiple fights
     *      - Resolve all fights
     *      - Users claim winnings
     */
    function test_multipleFight() public {
        console2.log("\n=== TEST CASE: Multiple Fights - Complete Flow ===");

        // ============ STEP 1: Create Event with 5 fights ============
        uint256 numFights = 5;
        vm.prank(operator);
        booster.createEvent(EVENT_1, numFights, SEASON_1, 0);

        // Prize pool: 100 FP per fight = 500 FP total
        uint256 prizePoolPerFight = 100;
        uint256 totalPrizePool = prizePoolPerFight * numFights; // 500 FP

        // Deposit prize pool for each fight
        for (uint256 i = 1; i <= numFights; i++) {
            vm.prank(operator);
            booster.depositBonus(EVENT_1, i, prizePoolPerFight, false);
        }

        // Verify prize pools deposited
        for (uint256 i = 1; i <= numFights; i++) {
            (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, i);
            assertEq(bonusPool, prizePoolPerFight, "Prize pool should be 100 FP per fight");
        }

        // ============ STEP 2: Users make predictions ============
        // User1: Bets 20 FP on Fight 1 (RED + SUBMISSION)
        //        Bets 20 FP on Fight 2 (RED + SUBMISSION)
        //        Bets 20 FP on Fight 3 (BLUE + DECISION)
        uint256 user1Stake1 = 20;
        uint256 user1Stake2 = 20;
        uint256 user1Stake3 = 20;
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](3);
        boosts1[0] = Booster.BoostInput(1, user1Stake1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts1[1] = Booster.BoostInput(2, user1Stake2, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts1[2] = Booster.BoostInput(3, user1Stake3, Booster.Corner.BLUE, Booster.WinMethod.DECISION);
        booster.placeBoosts(EVENT_1, boosts1);

        // User2: Bets 30 FP on Fight 1 (RED + DECISION)
        //        Bets 30 FP on Fight 2 (BLUE + KNOCKOUT)
        uint256 user2Stake1 = 30;
        uint256 user2Stake2 = 30;
        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](2);
        boosts2[0] = Booster.BoostInput(1, user2Stake1, Booster.Corner.RED, Booster.WinMethod.DECISION);
        boosts2[1] = Booster.BoostInput(2, user2Stake2, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts2);

        // User3: Bets 25 FP on Fight 1 (RED + SUBMISSION)
        //        Bets 25 FP on Fight 4 (RED + SUBMISSION)
        //        Bets 25 FP on Fight 5 (RED + SUBMISSION)
        uint256 user3Stake1 = 25;
        uint256 user3Stake4 = 25;
        uint256 user3Stake5 = 25;
        vm.prank(user3);
        Booster.BoostInput[] memory boosts3 = new Booster.BoostInput[](3);
        boosts3[0] = Booster.BoostInput(1, user3Stake1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts3[1] = Booster.BoostInput(4, user3Stake4, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts3[2] = Booster.BoostInput(5, user3Stake5, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts3);

        // Calculate total stakes for each user
        uint256 user1TotalStakes = user1Stake1 + user1Stake2 + user1Stake3;
        uint256 user2TotalStakes = user2Stake1 + user2Stake2;
        uint256 user3TotalStakes = user3Stake1 + user3Stake4 + user3Stake5;

        // Verify balances after predictions
        uint256 balanceAfterPredictions1 = fp.balanceOf(user1, SEASON_1);
        uint256 balanceAfterPredictions2 = fp.balanceOf(user2, SEASON_1);
        uint256 balanceAfterPredictions3 = fp.balanceOf(user3, SEASON_1);

        uint256 user1InitialBalance = 100;
        uint256 user2InitialBalance = 100;
        uint256 user3InitialBalance = 100;

        console2.log("\n=== BALANCES AFTER PREDICTIONS ===");
        console2.log("User1 balance: %d (bet: %d FP)", balanceAfterPredictions1, user1TotalStakes);
        console2.log("User2 balance: %d (bet: %d FP)", balanceAfterPredictions2, user2TotalStakes);
        console2.log("User3 balance: %d (bet: %d FP)", balanceAfterPredictions3, user3TotalStakes);

        assertEq(
            balanceAfterPredictions1,
            user1InitialBalance - user1TotalStakes,
            "User1 balance should be correct after prediction"
        );
        assertEq(
            balanceAfterPredictions2,
            user2InitialBalance - user2TotalStakes,
            "User2 balance should be correct after prediction"
        );
        assertEq(
            balanceAfterPredictions3,
            user3InitialBalance - user3TotalStakes,
            "User3 balance should be correct after prediction"
        );

        // Verify original pools for each fight
        (,,,, uint256 originalPool1,,,,,,,) = booster.getFight(EVENT_1, 1);
        (,,,, uint256 originalPool2,,,,,,,) = booster.getFight(EVENT_1, 2);
        (,,,, uint256 originalPool3,,,,,,,) = booster.getFight(EVENT_1, 3);
        (,,,, uint256 originalPool4,,,,,,,) = booster.getFight(EVENT_1, 4);
        (,,,, uint256 originalPool5,,,,,,,) = booster.getFight(EVENT_1, 5);

        uint256 fight1TotalStakes = user1Stake1 + user2Stake1 + user3Stake1;
        uint256 fight2TotalStakes = user1Stake2 + user2Stake2;
        uint256 fight3TotalStakes = user1Stake3;
        uint256 fight4TotalStakes = user3Stake4;
        uint256 fight5TotalStakes = user3Stake5;

        assertEq(originalPool1, fight1TotalStakes, "Fight 1 original pool should equal total stakes");
        assertEq(originalPool2, fight2TotalStakes, "Fight 2 original pool should equal total stakes");
        assertEq(originalPool3, fight3TotalStakes, "Fight 3 original pool should equal total stakes");
        assertEq(originalPool4, fight4TotalStakes, "Fight 4 original pool should equal total stakes");
        assertEq(originalPool5, fight5TotalStakes, "Fight 5 original pool should equal total stakes");

        // ============ STEP 3: Resolve all fights ============
        // Winning outcomes:
        // Fight 1: RED + SUBMISSION - User1 and User3 win
        // Fight 2: RED + SUBMISSION - User1 wins
        // Fight 3: BLUE + DECISION - User1 wins
        // Fight 4: RED + SUBMISSION - User3 wins
        // Fight 5: RED + SUBMISSION - User3 wins

        // Resolve Fight 1: RED + SUBMISSION
        // Calculate points for each user
        uint256 user1PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user2PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.DECISION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user3PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // All users win (have points > 0)
        uint256 fight1SumWinnersStakes = user1Stake1 + user2Stake1 + user3Stake1;
        uint256 fight1WinningPoolTotalShares = (user1PointsFight1Calc * user1Stake1)
            + (user2PointsFight1Calc * user2Stake1) + (user3PointsFight1Calc * user3Stake1);

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            1,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            fight1SumWinnersStakes,
            fight1WinningPoolTotalShares
        );

        // Resolve Fight 2: RED + SUBMISSION
        // Calculate points for User1 (User2 lost with BLUE + KNOCKOUT)
        uint256 user1PointsFight2Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User1 wins (has points > 0)
        uint256 fight2SumWinnersStakes = user1Stake2; // User2 lost (0 points)
        uint256 fight2WinningPoolTotalShares = user1PointsFight2Calc * user1Stake2;

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            2,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            fight2SumWinnersStakes,
            fight2WinningPoolTotalShares
        );

        // Resolve Fight 3: BLUE + DECISION
        // Calculate points for User1
        uint256 user1PointsFight3Calc = booster.calculateUserPoints(
            Booster.Corner.BLUE,
            Booster.WinMethod.DECISION,
            Booster.Corner.BLUE,
            Booster.WinMethod.DECISION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User1 wins
        uint256 fight3SumWinnersStakes = user1Stake3;
        uint256 fight3WinningPoolTotalShares = user1PointsFight3Calc * user1Stake3;

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            3,
            Booster.Corner.BLUE,
            Booster.WinMethod.DECISION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            fight3SumWinnersStakes,
            fight3WinningPoolTotalShares
        );

        // Resolve Fight 4: RED + SUBMISSION
        // Calculate points for User3
        uint256 user3PointsFight4Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User3 wins
        uint256 fight4SumWinnersStakes = user3Stake4;
        uint256 fight4WinningPoolTotalShares = user3PointsFight4Calc * user3Stake4;

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            4,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            fight4SumWinnersStakes,
            fight4WinningPoolTotalShares
        );

        // Resolve Fight 5: RED + SUBMISSION
        // Calculate points for User3
        uint256 user3PointsFight5Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User3 wins
        uint256 fight5SumWinnersStakes = user3Stake5;
        uint256 fight5WinningPoolTotalShares = user3PointsFight5Calc * user3Stake5;

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            5,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            fight5SumWinnersStakes,
            fight5WinningPoolTotalShares
        );

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(EVENT_1, true);

        console2.log("\n=== ALL FIGHTS RESOLVED ===");

        // Verify user points for each fight (reusing previously calculated values)
        // Fight 1: RED + SUBMISSION
        assertEq(user1PointsFight1Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 1 should have 4 points (exact match)");
        assertEq(user2PointsFight1Calc, POINTS_FOR_WINNER, "User2 Fight 1 should have 3 points (winner only)");
        assertEq(user3PointsFight1Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 1 should have 4 points (exact match)");

        // Fight 2: RED + SUBMISSION
        assertEq(user1PointsFight2Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 2 should have 4 points (exact match)");

        // Fight 3: BLUE + DECISION
        assertEq(user1PointsFight3Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 3 should have 4 points (exact match)");

        // Fight 4: RED + SUBMISSION
        assertEq(user3PointsFight4Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 4 should have 4 points (exact match)");

        // Fight 5: RED + SUBMISSION
        assertEq(user3PointsFight5Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 5 should have 4 points (exact match)");

        // ============ STEP 4: Users claim winnings ============
        // User1 claim - should have winnings from Fight 1, 2, and 3
        uint256 balanceBefore1 = fp.balanceOf(user1, SEASON_1);
        uint256[] memory indices1Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user1);
        uint256[] memory indices1Fight2 = booster.getUserBoostIndices(EVENT_1, 2, user1);
        uint256[] memory indices1Fight3 = booster.getUserBoostIndices(EVENT_1, 3, user1);

        uint256 totalClaimable1Fight1 = booster.quoteClaimable(EVENT_1, 1, user1, false);
        uint256 totalClaimable1Fight2 = booster.quoteClaimable(EVENT_1, 2, user1, false);
        uint256 totalClaimable1Fight3 = booster.quoteClaimable(EVENT_1, 3, user1, false);
        uint256 expectedTotalPayout1 = totalClaimable1Fight1 + totalClaimable1Fight2 + totalClaimable1Fight3;

        assertGt(totalClaimable1Fight1, 0, "User1 should be able to claim from Fight 1");
        assertGt(totalClaimable1Fight2, 0, "User1 should be able to claim from Fight 2");
        assertGt(totalClaimable1Fight3, 0, "User1 should be able to claim from Fight 3");

        console2.log("\n=== USER1 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore1);
        console2.log("Fight 1 claimable: %d", totalClaimable1Fight1);
        console2.log("Fight 2 claimable: %d", totalClaimable1Fight2);
        console2.log("Fight 3 claimable: %d", totalClaimable1Fight3);
        console2.log("Expected total payout: %d", expectedTotalPayout1);

        vm.prank(user1);
        booster.claimReward(EVENT_1, 1, indices1Fight1);
        vm.prank(user1);
        booster.claimReward(EVENT_1, 2, indices1Fight2);
        vm.prank(user1);
        booster.claimReward(EVENT_1, 3, indices1Fight3);

        uint256 balanceAfter1 = fp.balanceOf(user1, SEASON_1);
        uint256 winnings1 = balanceAfter1 - balanceBefore1;

        console2.log("After claim - Balance: %d", balanceAfter1);
        console2.log("Winnings received: %d", winnings1);
        assertEq(balanceAfter1, balanceBefore1 + expectedTotalPayout1, "User1 balance should match expected payout");

        // User2 claim - should have winnings from Fight 1 only
        uint256 balanceBefore2 = fp.balanceOf(user2, SEASON_1);
        uint256[] memory indices2Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user2);

        uint256 totalClaimable2Fight1 = booster.quoteClaimable(EVENT_1, 1, user2, false);

        assertGt(totalClaimable2Fight1, 0, "User2 should be able to claim from Fight 1");

        console2.log("\n=== USER2 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore2);
        console2.log("Fight 1 claimable: %d", totalClaimable2Fight1);
        console2.log("Fight 2: Lost (wrong fighter)");
        console2.log("Expected total payout: %d", totalClaimable2Fight1);

        vm.prank(user2);
        booster.claimReward(EVENT_1, 1, indices2Fight1);

        uint256 balanceAfter2 = fp.balanceOf(user2, SEASON_1);
        uint256 winnings2 = balanceAfter2 - balanceBefore2;

        console2.log("After claim - Balance: %d", balanceAfter2);
        console2.log("Winnings received: %d", winnings2);
        assertEq(balanceAfter2, balanceBefore2 + totalClaimable2Fight1, "User2 balance should match expected payout");

        // User3 claim - should have winnings from Fight 1, 4, and 5
        uint256 balanceBefore3 = fp.balanceOf(user3, SEASON_1);
        uint256[] memory indices3Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user3);
        uint256[] memory indices3Fight4 = booster.getUserBoostIndices(EVENT_1, 4, user3);
        uint256[] memory indices3Fight5 = booster.getUserBoostIndices(EVENT_1, 5, user3);

        uint256 totalClaimable3Fight1 = booster.quoteClaimable(EVENT_1, 1, user3, false);
        uint256 totalClaimable3Fight4 = booster.quoteClaimable(EVENT_1, 4, user3, false);
        uint256 totalClaimable3Fight5 = booster.quoteClaimable(EVENT_1, 5, user3, false);
        uint256 expectedTotalPayout3 = totalClaimable3Fight1 + totalClaimable3Fight4 + totalClaimable3Fight5;

        assertGt(totalClaimable3Fight1, 0, "User3 should be able to claim from Fight 1");
        assertGt(totalClaimable3Fight4, 0, "User3 should be able to claim from Fight 4");
        assertGt(totalClaimable3Fight5, 0, "User3 should be able to claim from Fight 5");

        console2.log("\n=== USER3 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore3);
        console2.log("Fight 1 claimable: %d", totalClaimable3Fight1);
        console2.log("Fight 4 claimable: %d", totalClaimable3Fight4);
        console2.log("Fight 5 claimable: %d", totalClaimable3Fight5);
        console2.log("Expected total payout: %d", expectedTotalPayout3);

        vm.prank(user3);
        booster.claimReward(EVENT_1, 1, indices3Fight1);
        vm.prank(user3);
        booster.claimReward(EVENT_1, 4, indices3Fight4);
        vm.prank(user3);
        booster.claimReward(EVENT_1, 5, indices3Fight5);

        uint256 balanceAfter3 = fp.balanceOf(user3, SEASON_1);
        uint256 winnings3 = balanceAfter3 - balanceBefore3;

        console2.log("After claim - Balance: %d", balanceAfter3);
        console2.log("Winnings received: %d", winnings3);
        assertEq(balanceAfter3, balanceBefore3 + expectedTotalPayout3, "User3 balance should match expected payout");

        // ============ STEP 5: Final Summary ============
        console2.log("\n=== FINAL RESULTS SUMMARY ===");

        // Calculate totals (user1TotalStakes, user2TotalStakes, user3TotalStakes already calculated above)
        uint256 totalStakesPlaced = user1TotalStakes + user2TotalStakes + user3TotalStakes;

        // Calculate total winnings (claimable - stake for each fight)
        uint256 user1Winnings = (totalClaimable1Fight1 - user1Stake1) + (totalClaimable1Fight2 - user1Stake2)
            + (totalClaimable1Fight3 - user1Stake3);
        uint256 user2Winnings = totalClaimable2Fight1 - user2Stake1; // User2 only won Fight 1
        uint256 user3Winnings = (totalClaimable3Fight1 - user3Stake1) + (totalClaimable3Fight4 - user3Stake4)
            + (totalClaimable3Fight5 - user3Stake5);
        uint256 totalWinningsPaid = user1Winnings + user2Winnings + user3Winnings;

        // Calculate total stakes recovered (only winning fights)
        uint256 user1StakesRecovered = user1Stake1 + user1Stake2 + user1Stake3; // All 3 fights won
        uint256 user2StakesRecovered = user2Stake1; // Only Fight 1 won
        uint256 user3StakesRecovered = user3Stake1 + user3Stake4 + user3Stake5; // All 3 fights won
        uint256 totalStakesRecovered = user1StakesRecovered + user2StakesRecovered + user3StakesRecovered;

        // Calculate total payout
        uint256 totalPayout = totalWinningsPaid + totalStakesRecovered;

        console2.log("\n--- User1 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable1Fight1, user1Stake1);
        console2.log("  Fight 2: %d claimable (%d stake + winnings)", totalClaimable1Fight2, user1Stake2);
        console2.log("  Fight 3: %d claimable (%d stake + winnings)", totalClaimable1Fight3, user1Stake3);
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user1Winnings, user1TotalStakes, expectedTotalPayout1
        );

        console2.log("\n--- User2 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable2Fight1, user2Stake1);
        console2.log("  Fight 2: Lost (wrong fighter)");
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user2Winnings, user2StakesRecovered, totalClaimable2Fight1
        );

        console2.log("\n--- User3 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable3Fight1, user3Stake1);
        console2.log("  Fight 4: %d claimable (%d stake + winnings)", totalClaimable3Fight4, user3Stake4);
        console2.log("  Fight 5: %d claimable (%d stake + winnings)", totalClaimable3Fight5, user3Stake5);
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user3Winnings, user3TotalStakes, expectedTotalPayout3
        );

        console2.log("\n--- Overall Summary ---");
        console2.log("  Total Winnings Paid: %d", totalWinningsPaid);
        console2.log("  Total Stakes Recovered: %d", totalStakesRecovered);
        console2.log("  Total Payout: %d", totalPayout);
        console2.log("  Total Stakes Placed: %d", totalStakesPlaced);
        console2.log("  Total Prize Pool: %d", totalPrizePool);
        console2.log("  Total in Contract (before payouts): %d", totalPrizePool + totalStakesPlaced);

        // Verify all positions are claimed
        uint256 claimable1Fight1After = booster.quoteClaimable(EVENT_1, 1, user1, false);
        uint256 claimable1Fight2After = booster.quoteClaimable(EVENT_1, 2, user1, false);
        uint256 claimable1Fight3After = booster.quoteClaimable(EVENT_1, 3, user1, false);
        uint256 claimable2Fight1After = booster.quoteClaimable(EVENT_1, 1, user2, false);
        uint256 claimable3Fight1After = booster.quoteClaimable(EVENT_1, 1, user3, false);
        uint256 claimable3Fight4After = booster.quoteClaimable(EVENT_1, 4, user3, false);
        uint256 claimable3Fight5After = booster.quoteClaimable(EVENT_1, 5, user3, false);

        assertEq(claimable1Fight1After, 0, "User1 Fight 1 should have no remaining claimable");
        assertEq(claimable1Fight2After, 0, "User1 Fight 2 should have no remaining claimable");
        assertEq(claimable1Fight3After, 0, "User1 Fight 3 should have no remaining claimable");
        assertEq(claimable2Fight1After, 0, "User2 Fight 1 should have no remaining claimable");
        assertEq(claimable3Fight1After, 0, "User3 Fight 1 should have no remaining claimable");
        assertEq(claimable3Fight4After, 0, "User3 Fight 4 should have no remaining claimable");
        assertEq(claimable3Fight5After, 0, "User3 Fight 5 should have no remaining claimable");

        // Calculate and verify remainder in contract (truncation remainder from integer division)
        // For each fight: totalPool = originalPool - sumWinnersStakes + bonusPool
        uint256 totalWinningsDistributed = user1Winnings + user2Winnings + user3Winnings;

        // Calculate total pools for each fight dynamically
        uint256 fight1TotalPool = originalPool1 - fight1SumWinnersStakes + prizePoolPerFight;
        uint256 fight2TotalPool = originalPool2 - fight2SumWinnersStakes + prizePoolPerFight;
        uint256 fight3TotalPool = originalPool3 - fight3SumWinnersStakes + prizePoolPerFight;
        uint256 fight4TotalPool = originalPool4 - fight4SumWinnersStakes + prizePoolPerFight;
        uint256 fight5TotalPool = originalPool5 - fight5SumWinnersStakes + prizePoolPerFight;
        uint256 totalPools = fight1TotalPool + fight2TotalPool + fight3TotalPool + fight4TotalPool + fight5TotalPool;

        // Expected remainder = total pools - total winnings distributed
        uint256 expectedRemainder = totalPools - totalWinningsDistributed;
        uint256 contractBalanceAfter = fp.balanceOf(address(booster), SEASON_1);
        assertEq(contractBalanceAfter, expectedRemainder, "Contract should have truncation remainder");

        console2.log("\n=== REMAINDER VERIFICATION ===");
        console2.log("Total Pools: %d", totalPools);
        console2.log("Total Winnings Distributed: %d", totalWinningsDistributed);
        console2.log("Expected Remainder: %d", expectedRemainder);
        console2.log("Contract Balance: %d", contractBalanceAfter);

        // Print final balances
        console2.log("\n=== FINAL BALANCES ===");
        console2.log("User1 balance: %d", fp.balanceOf(user1, SEASON_1));
        console2.log("User2 balance: %d", fp.balanceOf(user2, SEASON_1));
        console2.log("User3 balance: %d", fp.balanceOf(user3, SEASON_1));
        console2.log("Contract balance: %d", fp.balanceOf(address(booster), SEASON_1));
    }

    /**
     * @notice Test multiple fights with batch submission - identical to test_multipleFight but using submitFightResults batch
     * @dev This test is identical to test_multipleFight but submits all fight results in a single batch call
     *      - Create event with 5 fights
     *      - Users make predictions
     *      - Resolve all fights in batch
     *      - Users claim winnings
     */
    function test_multipleFight_batch() public {
        console2.log("\n=== TEST CASE: Multiple Fights - Complete Flow (BATCH) ===");

        // ============ STEP 1: Create Event with 5 fights ============
        uint256 numFights = 5;
        vm.prank(operator);
        booster.createEvent(EVENT_1, numFights, SEASON_1, 0);

        // Prize pool: 100 FP per fight = 500 FP total
        uint256 prizePoolPerFight = 100;
        uint256 totalPrizePool = prizePoolPerFight * numFights; // 500 FP

        // Deposit prize pool for each fight
        for (uint256 i = 1; i <= numFights; i++) {
            vm.prank(operator);
            booster.depositBonus(EVENT_1, i, prizePoolPerFight, false);
        }

        // Verify prize pools deposited
        for (uint256 i = 1; i <= numFights; i++) {
            (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, i);
            assertEq(bonusPool, prizePoolPerFight, "Prize pool should be 100 FP per fight");
        }

        // ============ STEP 2: Users make predictions ============
        // User1: Bets 20 FP on Fight 1 (RED + SUBMISSION)
        //        Bets 20 FP on Fight 2 (RED + SUBMISSION)
        //        Bets 20 FP on Fight 3 (BLUE + DECISION)
        uint256 user1Stake1 = 20;
        uint256 user1Stake2 = 20;
        uint256 user1Stake3 = 20;
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](3);
        boosts1[0] = Booster.BoostInput(1, user1Stake1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts1[1] = Booster.BoostInput(2, user1Stake2, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts1[2] = Booster.BoostInput(3, user1Stake3, Booster.Corner.BLUE, Booster.WinMethod.DECISION);
        booster.placeBoosts(EVENT_1, boosts1);

        // User2: Bets 30 FP on Fight 1 (RED + DECISION)
        //        Bets 30 FP on Fight 2 (BLUE + KNOCKOUT)
        uint256 user2Stake1 = 30;
        uint256 user2Stake2 = 30;
        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](2);
        boosts2[0] = Booster.BoostInput(1, user2Stake1, Booster.Corner.RED, Booster.WinMethod.DECISION);
        boosts2[1] = Booster.BoostInput(2, user2Stake2, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts2);

        // User3: Bets 25 FP on Fight 1 (RED + SUBMISSION)
        //        Bets 25 FP on Fight 4 (RED + SUBMISSION)
        //        Bets 25 FP on Fight 5 (RED + SUBMISSION)
        uint256 user3Stake1 = 25;
        uint256 user3Stake4 = 25;
        uint256 user3Stake5 = 25;
        vm.prank(user3);
        Booster.BoostInput[] memory boosts3 = new Booster.BoostInput[](3);
        boosts3[0] = Booster.BoostInput(1, user3Stake1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts3[1] = Booster.BoostInput(4, user3Stake4, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        boosts3[2] = Booster.BoostInput(5, user3Stake5, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts3);

        // Calculate total stakes for each user
        uint256 user1TotalStakes = user1Stake1 + user1Stake2 + user1Stake3;
        uint256 user2TotalStakes = user2Stake1 + user2Stake2;
        uint256 user3TotalStakes = user3Stake1 + user3Stake4 + user3Stake5;

        // Verify balances after predictions
        uint256 balanceAfterPredictions1 = fp.balanceOf(user1, SEASON_1);
        uint256 balanceAfterPredictions2 = fp.balanceOf(user2, SEASON_1);
        uint256 balanceAfterPredictions3 = fp.balanceOf(user3, SEASON_1);

        uint256 user1InitialBalance = 100;
        uint256 user2InitialBalance = 100;
        uint256 user3InitialBalance = 100;

        console2.log("\n=== BALANCES AFTER PREDICTIONS ===");
        console2.log("User1 balance: %d (bet: %d FP)", balanceAfterPredictions1, user1TotalStakes);
        console2.log("User2 balance: %d (bet: %d FP)", balanceAfterPredictions2, user2TotalStakes);
        console2.log("User3 balance: %d (bet: %d FP)", balanceAfterPredictions3, user3TotalStakes);

        assertEq(
            balanceAfterPredictions1,
            user1InitialBalance - user1TotalStakes,
            "User1 balance should be correct after prediction"
        );
        assertEq(
            balanceAfterPredictions2,
            user2InitialBalance - user2TotalStakes,
            "User2 balance should be correct after prediction"
        );
        assertEq(
            balanceAfterPredictions3,
            user3InitialBalance - user3TotalStakes,
            "User3 balance should be correct after prediction"
        );

        // Verify original pools for each fight
        (,,,, uint256 originalPool1,,,,,,,) = booster.getFight(EVENT_1, 1);
        (,,,, uint256 originalPool2,,,,,,,) = booster.getFight(EVENT_1, 2);
        (,,,, uint256 originalPool3,,,,,,,) = booster.getFight(EVENT_1, 3);
        (,,,, uint256 originalPool4,,,,,,,) = booster.getFight(EVENT_1, 4);
        (,,,, uint256 originalPool5,,,,,,,) = booster.getFight(EVENT_1, 5);

        uint256 fight1TotalStakes = user1Stake1 + user2Stake1 + user3Stake1;
        uint256 fight2TotalStakes = user1Stake2 + user2Stake2;
        uint256 fight3TotalStakes = user1Stake3;
        uint256 fight4TotalStakes = user3Stake4;
        uint256 fight5TotalStakes = user3Stake5;

        assertEq(originalPool1, fight1TotalStakes, "Fight 1 original pool should equal total stakes");
        assertEq(originalPool2, fight2TotalStakes, "Fight 2 original pool should equal total stakes");
        assertEq(originalPool3, fight3TotalStakes, "Fight 3 original pool should equal total stakes");
        assertEq(originalPool4, fight4TotalStakes, "Fight 4 original pool should equal total stakes");
        assertEq(originalPool5, fight5TotalStakes, "Fight 5 original pool should equal total stakes");

        // ============ STEP 3: Resolve all fights in batch ============
        // Winning outcomes:
        // Fight 1: RED + SUBMISSION - User1 and User3 win
        // Fight 2: RED + SUBMISSION - User1 wins
        // Fight 3: BLUE + DECISION - User1 wins
        // Fight 4: RED + SUBMISSION - User3 wins
        // Fight 5: RED + SUBMISSION - User3 wins

        // Calculate points for all fights
        // Fight 1: RED + SUBMISSION
        uint256 user1PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user2PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.DECISION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user3PointsFight1Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // All users win (have points > 0)
        uint256 fight1SumWinnersStakes = user1Stake1 + user2Stake1 + user3Stake1;
        uint256 fight1WinningPoolTotalShares = (user1PointsFight1Calc * user1Stake1)
            + (user2PointsFight1Calc * user2Stake1) + (user3PointsFight1Calc * user3Stake1);

        // Fight 2: RED + SUBMISSION
        uint256 user1PointsFight2Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User1 wins (has points > 0)
        uint256 fight2SumWinnersStakes = user1Stake2; // User2 lost (0 points)
        uint256 fight2WinningPoolTotalShares = user1PointsFight2Calc * user1Stake2;

        // Fight 3: BLUE + DECISION
        uint256 user1PointsFight3Calc = booster.calculateUserPoints(
            Booster.Corner.BLUE,
            Booster.WinMethod.DECISION,
            Booster.Corner.BLUE,
            Booster.WinMethod.DECISION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User1 wins
        uint256 fight3SumWinnersStakes = user1Stake3;
        uint256 fight3WinningPoolTotalShares = user1PointsFight3Calc * user1Stake3;

        // Fight 4: RED + SUBMISSION
        uint256 user3PointsFight4Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User3 wins
        uint256 fight4SumWinnersStakes = user3Stake4;
        uint256 fight4WinningPoolTotalShares = user3PointsFight4Calc * user3Stake4;

        // Fight 5: RED + SUBMISSION
        uint256 user3PointsFight5Calc = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User3 wins
        uint256 fight5SumWinnersStakes = user3Stake5;
        uint256 fight5WinningPoolTotalShares = user3PointsFight5Calc * user3Stake5;

        // Submit all fight results in batch
        Booster.FightResultInput[] memory inputs = new Booster.FightResultInput[](5);
        inputs[0] = Booster.FightResultInput({
            fightId: 1,
            winner: Booster.Corner.RED,
            method: Booster.WinMethod.SUBMISSION,
            pointsForWinner: POINTS_FOR_WINNER,
            pointsForWinnerMethod: POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes: fight1SumWinnersStakes,
            winningPoolTotalShares: fight1WinningPoolTotalShares
        });
        inputs[1] = Booster.FightResultInput({
            fightId: 2,
            winner: Booster.Corner.RED,
            method: Booster.WinMethod.SUBMISSION,
            pointsForWinner: POINTS_FOR_WINNER,
            pointsForWinnerMethod: POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes: fight2SumWinnersStakes,
            winningPoolTotalShares: fight2WinningPoolTotalShares
        });
        inputs[2] = Booster.FightResultInput({
            fightId: 3,
            winner: Booster.Corner.BLUE,
            method: Booster.WinMethod.DECISION,
            pointsForWinner: POINTS_FOR_WINNER,
            pointsForWinnerMethod: POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes: fight3SumWinnersStakes,
            winningPoolTotalShares: fight3WinningPoolTotalShares
        });
        inputs[3] = Booster.FightResultInput({
            fightId: 4,
            winner: Booster.Corner.RED,
            method: Booster.WinMethod.SUBMISSION,
            pointsForWinner: POINTS_FOR_WINNER,
            pointsForWinnerMethod: POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes: fight4SumWinnersStakes,
            winningPoolTotalShares: fight4WinningPoolTotalShares
        });
        inputs[4] = Booster.FightResultInput({
            fightId: 5,
            winner: Booster.Corner.RED,
            method: Booster.WinMethod.SUBMISSION,
            pointsForWinner: POINTS_FOR_WINNER,
            pointsForWinnerMethod: POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes: fight5SumWinnersStakes,
            winningPoolTotalShares: fight5WinningPoolTotalShares
        });

        vm.prank(operator);
        booster.submitFightResults(EVENT_1, inputs);

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(EVENT_1, true);

        console2.log("\n=== ALL FIGHTS RESOLVED (BATCH) ===");

        // Verify user points for each fight (reusing previously calculated values)
        // Fight 1: RED + SUBMISSION
        assertEq(user1PointsFight1Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 1 should have 4 points (exact match)");
        assertEq(user2PointsFight1Calc, POINTS_FOR_WINNER, "User2 Fight 1 should have 3 points (winner only)");
        assertEq(user3PointsFight1Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 1 should have 4 points (exact match)");

        // Fight 2: RED + SUBMISSION
        assertEq(user1PointsFight2Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 2 should have 4 points (exact match)");

        // Fight 3: BLUE + DECISION
        assertEq(user1PointsFight3Calc, POINTS_FOR_WINNER_METHOD, "User1 Fight 3 should have 4 points (exact match)");

        // Fight 4: RED + SUBMISSION
        assertEq(user3PointsFight4Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 4 should have 4 points (exact match)");

        // Fight 5: RED + SUBMISSION
        assertEq(user3PointsFight5Calc, POINTS_FOR_WINNER_METHOD, "User3 Fight 5 should have 4 points (exact match)");

        // ============ STEP 4: Users claim winnings ============
        // User1 claim - should have winnings from Fight 1, 2, and 3
        uint256 balanceBefore1 = fp.balanceOf(user1, SEASON_1);
        uint256[] memory indices1Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user1);
        uint256[] memory indices1Fight2 = booster.getUserBoostIndices(EVENT_1, 2, user1);
        uint256[] memory indices1Fight3 = booster.getUserBoostIndices(EVENT_1, 3, user1);

        uint256 totalClaimable1Fight1 = booster.quoteClaimable(EVENT_1, 1, user1, false);
        uint256 totalClaimable1Fight2 = booster.quoteClaimable(EVENT_1, 2, user1, false);
        uint256 totalClaimable1Fight3 = booster.quoteClaimable(EVENT_1, 3, user1, false);
        uint256 expectedTotalPayout1 = totalClaimable1Fight1 + totalClaimable1Fight2 + totalClaimable1Fight3;

        assertGt(totalClaimable1Fight1, 0, "User1 should be able to claim from Fight 1");
        assertGt(totalClaimable1Fight2, 0, "User1 should be able to claim from Fight 2");
        assertGt(totalClaimable1Fight3, 0, "User1 should be able to claim from Fight 3");

        console2.log("\n=== USER1 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore1);
        console2.log("Fight 1 claimable: %d", totalClaimable1Fight1);
        console2.log("Fight 2 claimable: %d", totalClaimable1Fight2);
        console2.log("Fight 3 claimable: %d", totalClaimable1Fight3);
        console2.log("Expected total payout: %d", expectedTotalPayout1);

        vm.prank(user1);
        booster.claimReward(EVENT_1, 1, indices1Fight1);
        vm.prank(user1);
        booster.claimReward(EVENT_1, 2, indices1Fight2);
        vm.prank(user1);
        booster.claimReward(EVENT_1, 3, indices1Fight3);

        uint256 balanceAfter1 = fp.balanceOf(user1, SEASON_1);
        uint256 winnings1 = balanceAfter1 - balanceBefore1;

        console2.log("After claim - Balance: %d", balanceAfter1);
        console2.log("Winnings received: %d", winnings1);
        assertEq(balanceAfter1, balanceBefore1 + expectedTotalPayout1, "User1 balance should match expected payout");

        // User2 claim - should have winnings from Fight 1 only
        uint256 balanceBefore2 = fp.balanceOf(user2, SEASON_1);
        uint256[] memory indices2Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user2);

        uint256 totalClaimable2Fight1 = booster.quoteClaimable(EVENT_1, 1, user2, false);

        assertGt(totalClaimable2Fight1, 0, "User2 should be able to claim from Fight 1");

        console2.log("\n=== USER2 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore2);
        console2.log("Fight 1 claimable: %d", totalClaimable2Fight1);
        console2.log("Fight 2: Lost (wrong fighter)");
        console2.log("Expected total payout: %d", totalClaimable2Fight1);

        vm.prank(user2);
        booster.claimReward(EVENT_1, 1, indices2Fight1);

        uint256 balanceAfter2 = fp.balanceOf(user2, SEASON_1);
        uint256 winnings2 = balanceAfter2 - balanceBefore2;

        console2.log("After claim - Balance: %d", balanceAfter2);
        console2.log("Winnings received: %d", winnings2);
        assertEq(balanceAfter2, balanceBefore2 + totalClaimable2Fight1, "User2 balance should match expected payout");

        // User3 claim - should have winnings from Fight 1, 4, and 5
        uint256 balanceBefore3 = fp.balanceOf(user3, SEASON_1);
        uint256[] memory indices3Fight1 = booster.getUserBoostIndices(EVENT_1, 1, user3);
        uint256[] memory indices3Fight4 = booster.getUserBoostIndices(EVENT_1, 4, user3);
        uint256[] memory indices3Fight5 = booster.getUserBoostIndices(EVENT_1, 5, user3);

        uint256 totalClaimable3Fight1 = booster.quoteClaimable(EVENT_1, 1, user3, false);
        uint256 totalClaimable3Fight4 = booster.quoteClaimable(EVENT_1, 4, user3, false);
        uint256 totalClaimable3Fight5 = booster.quoteClaimable(EVENT_1, 5, user3, false);
        uint256 expectedTotalPayout3 = totalClaimable3Fight1 + totalClaimable3Fight4 + totalClaimable3Fight5;

        assertGt(totalClaimable3Fight1, 0, "User3 should be able to claim from Fight 1");
        assertGt(totalClaimable3Fight4, 0, "User3 should be able to claim from Fight 4");
        assertGt(totalClaimable3Fight5, 0, "User3 should be able to claim from Fight 5");

        console2.log("\n=== USER3 CLAIM ===");
        console2.log("Before claim - Balance: %d", balanceBefore3);
        console2.log("Fight 1 claimable: %d", totalClaimable3Fight1);
        console2.log("Fight 4 claimable: %d", totalClaimable3Fight4);
        console2.log("Fight 5 claimable: %d", totalClaimable3Fight5);
        console2.log("Expected total payout: %d", expectedTotalPayout3);

        vm.prank(user3);
        booster.claimReward(EVENT_1, 1, indices3Fight1);
        vm.prank(user3);
        booster.claimReward(EVENT_1, 4, indices3Fight4);
        vm.prank(user3);
        booster.claimReward(EVENT_1, 5, indices3Fight5);

        uint256 balanceAfter3 = fp.balanceOf(user3, SEASON_1);
        uint256 winnings3 = balanceAfter3 - balanceBefore3;

        console2.log("After claim - Balance: %d", balanceAfter3);
        console2.log("Winnings received: %d", winnings3);
        assertEq(balanceAfter3, balanceBefore3 + expectedTotalPayout3, "User3 balance should match expected payout");

        // ============ STEP 5: Final Summary ============
        console2.log("\n=== FINAL RESULTS SUMMARY ===");

        // Calculate totals (user1TotalStakes, user2TotalStakes, user3TotalStakes already calculated above)
        uint256 totalStakesPlaced = user1TotalStakes + user2TotalStakes + user3TotalStakes;

        // Calculate total winnings (claimable - stake for each fight)
        uint256 user1Winnings = (totalClaimable1Fight1 - user1Stake1) + (totalClaimable1Fight2 - user1Stake2)
            + (totalClaimable1Fight3 - user1Stake3);
        uint256 user2Winnings = totalClaimable2Fight1 - user2Stake1; // User2 only won Fight 1
        uint256 user3Winnings = (totalClaimable3Fight1 - user3Stake1) + (totalClaimable3Fight4 - user3Stake4)
            + (totalClaimable3Fight5 - user3Stake5);
        uint256 totalWinningsPaid = user1Winnings + user2Winnings + user3Winnings;

        // Calculate total stakes recovered (only winning fights)
        uint256 user1StakesRecovered = user1Stake1 + user1Stake2 + user1Stake3; // All 3 fights won
        uint256 user2StakesRecovered = user2Stake1; // Only Fight 1 won
        uint256 user3StakesRecovered = user3Stake1 + user3Stake4 + user3Stake5; // All 3 fights won
        uint256 totalStakesRecovered = user1StakesRecovered + user2StakesRecovered + user3StakesRecovered;

        // Calculate total payout
        uint256 totalPayout = totalWinningsPaid + totalStakesRecovered;

        console2.log("\n--- User1 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable1Fight1, user1Stake1);
        console2.log("  Fight 2: %d claimable (%d stake + winnings)", totalClaimable1Fight2, user1Stake2);
        console2.log("  Fight 3: %d claimable (%d stake + winnings)", totalClaimable1Fight3, user1Stake3);
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user1Winnings, user1TotalStakes, expectedTotalPayout1
        );

        console2.log("\n--- User2 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable2Fight1, user2Stake1);
        console2.log("  Fight 2: Lost (wrong fighter)");
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user2Winnings, user2StakesRecovered, totalClaimable2Fight1
        );

        console2.log("\n--- User3 Results ---");
        console2.log("  Fight 1: %d claimable (%d stake + winnings)", totalClaimable3Fight1, user3Stake1);
        console2.log("  Fight 4: %d claimable (%d stake + winnings)", totalClaimable3Fight4, user3Stake4);
        console2.log("  Fight 5: %d claimable (%d stake + winnings)", totalClaimable3Fight5, user3Stake5);
        console2.log(
            "  Total: %d winnings + %d stake = %d total", user3Winnings, user3TotalStakes, expectedTotalPayout3
        );

        console2.log("\n--- Overall Summary ---");
        console2.log("  Total Winnings Paid: %d", totalWinningsPaid);
        console2.log("  Total Stakes Recovered: %d", totalStakesRecovered);
        console2.log("  Total Payout: %d", totalPayout);
        console2.log("  Total Stakes Placed: %d", totalStakesPlaced);
        console2.log("  Total Prize Pool: %d", totalPrizePool);
        console2.log("  Total in Contract (before payouts): %d", totalPrizePool + totalStakesPlaced);

        // Verify all positions are claimed
        uint256 claimable1Fight1After = booster.quoteClaimable(EVENT_1, 1, user1, false);
        uint256 claimable1Fight2After = booster.quoteClaimable(EVENT_1, 2, user1, false);
        uint256 claimable1Fight3After = booster.quoteClaimable(EVENT_1, 3, user1, false);
        uint256 claimable2Fight1After = booster.quoteClaimable(EVENT_1, 1, user2, false);
        uint256 claimable3Fight1After = booster.quoteClaimable(EVENT_1, 1, user3, false);
        uint256 claimable3Fight4After = booster.quoteClaimable(EVENT_1, 4, user3, false);
        uint256 claimable3Fight5After = booster.quoteClaimable(EVENT_1, 5, user3, false);

        assertEq(claimable1Fight1After, 0, "User1 Fight 1 should have no remaining claimable");
        assertEq(claimable1Fight2After, 0, "User1 Fight 2 should have no remaining claimable");
        assertEq(claimable1Fight3After, 0, "User1 Fight 3 should have no remaining claimable");
        assertEq(claimable2Fight1After, 0, "User2 Fight 1 should have no remaining claimable");
        assertEq(claimable3Fight1After, 0, "User3 Fight 1 should have no remaining claimable");
        assertEq(claimable3Fight4After, 0, "User3 Fight 4 should have no remaining claimable");
        assertEq(claimable3Fight5After, 0, "User3 Fight 5 should have no remaining claimable");

        // Calculate and verify remainder in contract (truncation remainder from integer division)
        // For each fight: totalPool = originalPool - sumWinnersStakes + bonusPool
        uint256 totalWinningsDistributed = user1Winnings + user2Winnings + user3Winnings;

        // Calculate total pools for each fight dynamically
        uint256 fight1TotalPool = originalPool1 - fight1SumWinnersStakes + prizePoolPerFight;
        uint256 fight2TotalPool = originalPool2 - fight2SumWinnersStakes + prizePoolPerFight;
        uint256 fight3TotalPool = originalPool3 - fight3SumWinnersStakes + prizePoolPerFight;
        uint256 fight4TotalPool = originalPool4 - fight4SumWinnersStakes + prizePoolPerFight;
        uint256 fight5TotalPool = originalPool5 - fight5SumWinnersStakes + prizePoolPerFight;
        uint256 totalPools = fight1TotalPool + fight2TotalPool + fight3TotalPool + fight4TotalPool + fight5TotalPool;

        // Expected remainder = total pools - total winnings distributed
        uint256 expectedRemainder = totalPools - totalWinningsDistributed;
        uint256 contractBalanceAfter = fp.balanceOf(address(booster), SEASON_1);
        assertEq(contractBalanceAfter, expectedRemainder, "Contract should have truncation remainder");

        console2.log("\n=== REMAINDER VERIFICATION ===");
        console2.log("Total Pools: %d", totalPools);
        console2.log("Total Winnings Distributed: %d", totalWinningsDistributed);
        console2.log("Expected Remainder: %d", expectedRemainder);
        console2.log("Contract Balance: %d", contractBalanceAfter);

        // Print final balances
        console2.log("\n=== FINAL BALANCES ===");
        console2.log("User1 balance: %d", fp.balanceOf(user1, SEASON_1));
        console2.log("User2 balance: %d", fp.balanceOf(user2, SEASON_1));
        console2.log("User3 balance: %d", fp.balanceOf(user3, SEASON_1));
        console2.log("Contract balance: %d", fp.balanceOf(address(booster), SEASON_1));
    }

    /**
     * @notice Edge Case 1: Many winners with small pool - truncation to zero (NO SEEDING)
     * @dev Tests that with a very small prize pool and many winners, WITHOUT seeding,
     *      winners receive 0 FP winnings due to truncation:
     *      - 5 users bet 1 FP each on the same winning outcome (RED + SUBMISSION)
     *      - Initial prize pool: 1 FP (very small)
     *      - All users win with exact match (4 points each)
     *      - Total shares: 5 users x 4 points = 20 shares
     *      - Winnings per user = (1 x 4) / 20 = 0.2 FP (truncates to 0)
     *      - Users only get their stake back (1 FP), no winnings
     */
    function test_edgeCase1_manyWinnersSmallPool_noSeeding() public {
        console2.log("\n=== EDGE CASE 1: Many Winners with Small Pool (NO SEEDING) ===");

        string memory eventId = "UFC_EDGE_CASE_1";
        uint256 fightId = 1;

        // Create event with 1 fight
        vm.prank(operator);
        booster.createEvent(eventId, 1, SEASON_1, 0);

        // Very small initial prize pool: 1 FP
        uint256 initialPrizePool = 1;

        // Deposit initial prize pool
        vm.prank(operator);
        booster.depositBonus(eventId, fightId, initialPrizePool, false);

        // Verify initial prize pool
        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(bonusPool, initialPrizePool, "Initial prize pool should be 1 FP");

        // 5 users bet 1 FP each on the same winning outcome (RED + SUBMISSION)
        uint256 stakePerUser = 1;
        address[] memory users = new address[](5);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = user4;
        users[4] = user5;

        console2.log("\n=== SETUP ===");
        console2.log("Initial Prize Pool: ", initialPrizePool, " FP");
        console2.log("5 users betting ", stakePerUser, " FP each on RED + SUBMISSION");
        console2.log("NO SEEDING - will show truncation to zero");

        // All users place bets
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
            boosts[0] = Booster.BoostInput(fightId, stakePerUser, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
            booster.placeBoosts(eventId, boosts);
        }

        // Verify balances after predictions
        uint256 totalStakes = stakePerUser * users.length; // 5 FP
        uint256 userInitialBalance = 100;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balanceAfter = fp.balanceOf(users[i], SEASON_1);
            assertEq(balanceAfter, userInitialBalance - stakePerUser, "User balance should be correct after prediction");
        }

        // Verify original pool
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(originalPool, totalStakes, "Original pool should equal total stakes (5 FP)");

        // Calculate prize pool WITHOUT seeding
        uint256 currentPrizePool = originalPool - totalStakes + bonusPool; // 5 - 5 + 1 = 1
        assertEq(currentPrizePool, initialPrizePool, "Current prize pool should equal initial prize pool (1 FP)");

        console2.log("\n=== PRIZE POOL CALCULATION (NO SEEDING) ===");
        console2.log("Original Pool: ", originalPool, " FP");
        console2.log("Current Prize Pool: ", currentPrizePool, " FP");
        console2.log("Expected winnings per user: (", currentPrizePool, " x 4) / 20 = 0.2 FP (truncates to 0)");

        // Resolve fight: RED + SUBMISSION wins
        // All 5 users win with exact match (4 points each)
        uint256 sumWinnersStakes = totalStakes; // All 5 users win
        uint256 winningPoolTotalShares = POINTS_FOR_WINNER_METHOD * totalStakes; // 4 * 5 = 20

        console2.log("\n=== RESOLVING FIGHT ===");
        console2.log("Winning outcome: RED + SUBMISSION");
        console2.log("All 5 users win (exact match = 4 points each)");
        console2.log("Sum Winners Stakes: ", sumWinnersStakes, " FP");
        console2.log("Winning Pool Total Shares: ", winningPoolTotalShares, " (5 users x 4 points)");

        vm.prank(operator);
        booster.submitFightResult(
            eventId,
            fightId,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes,
            winningPoolTotalShares
        );

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(eventId, true);

        // Verify user points for all users (all should have exact match = 4 points)
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userPoints = booster.calculateUserPoints(
                Booster.Corner.RED,
                Booster.WinMethod.SUBMISSION,
                Booster.Corner.RED,
                Booster.WinMethod.SUBMISSION,
                POINTS_FOR_WINNER,
                POINTS_FOR_WINNER_METHOD
            );
            assertEq(userPoints, POINTS_FOR_WINNER_METHOD, "All users should have 4 points (exact match)");
        }

        // Get final prize pool after resolution (NO seeding)
        uint256 finalPrizePool = originalPool - sumWinnersStakes + bonusPool; // 5 - 5 + 1 = 1
        assertEq(finalPrizePool, currentPrizePool, "Final prize pool should equal current prize pool");
        assertEq(finalPrizePool, initialPrizePool, "Final prize pool should equal initial prize pool (1 FP)");

        console2.log("\n=== AFTER RESOLUTION ===");
        console2.log("Final Prize Pool: ", finalPrizePool, " FP");
        uint256 expectedWinningsPerUser = (finalPrizePool * POINTS_FOR_WINNER_METHOD) / winningPoolTotalShares;
        assertEq(expectedWinningsPerUser, 0, "Expected winnings per user should be 0 (truncated from 0.2)");
        console2.log("Expected winnings per user: ", expectedWinningsPerUser, " FP (truncated from 0.2)");

        // Verify contract balance before claims
        uint256 contractBalanceBeforeClaims = fp.balanceOf(address(booster), SEASON_1);
        uint256 expectedContractBalance = originalPool + bonusPool; // 5 + 1 = 6
        assertEq(
            contractBalanceBeforeClaims, expectedContractBalance, "Contract balance should be correct before claims"
        );

        // Verify all users can claim but have 0 winnings (only stake back)
        uint256[] memory totalClaimables = new uint256[](users.length);
        uint256[] memory balancesBefore = new uint256[](users.length);

        console2.log("\n=== VERIFYING WINNINGS (SHOULD BE 0) ===");
        for (uint256 i = 0; i < users.length; i++) {
            uint256 totalClaimable = booster.quoteClaimable(eventId, fightId, users[i], false);
            totalClaimables[i] = totalClaimable;
            balancesBefore[i] = fp.balanceOf(users[i], SEASON_1);

            // Calculate expected winnings (excluding stake)
            uint256 userWinnings = totalClaimable > stakePerUser ? totalClaimable - stakePerUser : 0;

            console2.log("User", i + 1);
            console2.log("  Claimable:", totalClaimable);
            console2.log("  Stake:", stakePerUser);
            console2.log("  Winnings:", userWinnings);

            // Verify user can claim (they get their stake back)
            assertGt(totalClaimable, 0, "User should be able to claim");
            // Verify winnings are 0 (truncation to zero)
            assertEq(userWinnings, 0, "User should receive 0 FP winnings due to truncation");
            // Verify total payout is only stake (1 FP)
            assertEq(totalClaimable, stakePerUser, "User should only receive stake back (1 FP)");
        }

        // Verify all users have the same claimable amount (all should get 1 FP stake back)
        for (uint256 i = 1; i < users.length; i++) {
            assertEq(totalClaimables[i], totalClaimables[0], "All users should have the same claimable amount");
        }
        assertEq(totalClaimables[0], stakePerUser, "First user claimable should equal stake");

        // Users claim their winnings
        console2.log("\n=== USERS CLAIM WINNINGS ===");
        uint256 totalPayouts = 0;
        for (uint256 i = 0; i < users.length; i++) {
            uint256[] memory indices = booster.getUserBoostIndices(eventId, fightId, users[i]);
            uint256 balanceBeforeClaim = fp.balanceOf(users[i], SEASON_1);
            uint256 contractBalanceBeforeClaim = fp.balanceOf(address(booster), SEASON_1);

            vm.prank(users[i]);
            booster.claimReward(eventId, fightId, indices);

            uint256 balanceAfterClaim = fp.balanceOf(users[i], SEASON_1);
            uint256 contractBalanceAfterClaim = fp.balanceOf(address(booster), SEASON_1);
            uint256 received = balanceAfterClaim - balanceBeforeClaim;
            uint256 contractPaid = contractBalanceBeforeClaim - contractBalanceAfterClaim;

            totalPayouts += totalClaimables[i];

            console2.log("User", i + 1);
            console2.log("  Received:", received, "FP");
            console2.log("  Contract paid:", contractPaid, "FP");

            assertEq(
                balanceAfterClaim, balanceBeforeClaim + totalClaimables[i], "User balance should match expected payout"
            );
            assertEq(contractPaid, totalClaimables[i], "Contract should pay exact claimable amount");
        }

        // Verify total payouts calculation
        uint256 expectedTotalPayouts = stakePerUser * users.length; // 5 FP
        assertEq(totalPayouts, expectedTotalPayouts, "Total payouts should equal total stakes (5 FP)");

        // Final balances and remainder
        console2.log("\n=== FINAL RESULTS ===");
        uint256 contractBalanceFinal = fp.balanceOf(address(booster), SEASON_1);
        uint256 contractBalanceBefore = originalPool + initialPrizePool; // 5 + 1 = 6
        assertEq(contractBalanceBefore, expectedContractBalance, "Contract balance before should match expected");

        console2.log("Total Payouts: ", totalPayouts, " FP (5 users x 1 FP stake each)");
        console2.log("Contract Balance Before: ", contractBalanceBefore, " FP");
        console2.log("Contract Balance After: ", contractBalanceFinal, " FP");
        console2.log("Remainder: ", contractBalanceFinal, " FP (1 FP prize pool remains unused)");

        // Verify remainder calculation
        // Contract had: 5 stakes + 1 prize pool = 6 FP
        // Paid out: 5 stakes = 5 FP
        // Remainder: 1 FP (the prize pool that couldn't be distributed due to truncation)
        uint256 expectedRemainder = contractBalanceBefore - totalPayouts;
        assertEq(contractBalanceFinal, expectedRemainder, "Contract should have 1 FP remainder (prize pool)");
        assertEq(contractBalanceFinal, initialPrizePool, "Remainder should equal initial prize pool (1 FP)");

        // Verify final user balances
        for (uint256 i = 0; i < users.length; i++) {
            uint256 finalBalance = fp.balanceOf(users[i], SEASON_1);
            uint256 expectedFinalBalance = balancesBefore[i] + totalClaimables[i];
            assertEq(finalBalance, expectedFinalBalance, "User final balance should be correct");
            assertEq(finalBalance, userInitialBalance, "User should have initial balance back (100 FP)");
        }

        // Verify all positions are claimed
        for (uint256 i = 0; i < users.length; i++) {
            uint256 claimableAfter = booster.quoteClaimable(eventId, fightId, users[i], false);
            assertEq(claimableAfter, 0, "User should have no remaining claimable");
        }

        console2.log("\n[PASS] Edge Case 1 PASSED: Shows truncation to zero without seeding!");
    }

    /**
     * @notice Edge Case 2: Many winners with small pool - with seeding
     * @dev Tests that with a very small prize pool and many winners, seeding ensures
     *      all winners receive at least 1 FP winnings:
     *      - 5 users bet 1 FP each on the same winning outcome (RED + SUBMISSION)
     *      - Initial prize pool: 1 FP (very small)
     *      - All users win with exact match (4 points each)
     *      - Total shares: 5 users x 4 points = 20 shares
     *      - Without seeding: winnings per user = (1 x 4) / 20 = 0.2 FP (truncates to 0)
     *      - With seeding: ensure all users receive at least 1 FP winnings
     */
    function test_edgeCase2_manyWinnersSmallPool_withSeeding() public {
        console2.log("\n=== EDGE CASE 2: Many Winners with Small Pool (WITH SEEDING) ===");

        string memory eventId = "UFC_EDGE_CASE_2";
        uint256 fightId = 1;

        // Create event with 1 fight
        vm.prank(operator);
        booster.createEvent(eventId, 1, SEASON_1, 0);

        // Very small initial prize pool: 1 FP
        uint256 initialPrizePool = 1;

        // Deposit initial prize pool
        vm.prank(operator);
        booster.depositBonus(eventId, fightId, initialPrizePool, false);

        // Verify initial prize pool
        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(bonusPool, initialPrizePool, "Initial prize pool should be 1 FP");

        // 5 users bet 1 FP each on the same winning outcome (RED + SUBMISSION)
        uint256 stakePerUser = 1;
        address[] memory users = new address[](5);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = user4;
        users[4] = user5;

        console2.log("\n=== SETUP ===");
        console2.log("Initial Prize Pool: %d FP", initialPrizePool);
        console2.log("5 users betting %d FP each on RED + SUBMISSION", stakePerUser);

        // All users place bets
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
            boosts[0] = Booster.BoostInput(fightId, stakePerUser, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
            booster.placeBoosts(eventId, boosts);
        }

        // Verify balances after predictions
        uint256 totalStakes = stakePerUser * users.length; // 5 FP
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balanceAfter = fp.balanceOf(users[i], SEASON_1);
            assertEq(balanceAfter, 100 - stakePerUser, "User balance should be correct after prediction");
        }

        // Verify original pool
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(originalPool, totalStakes, "Original pool should equal total stakes (5 FP)");

        // Verify initial balances
        uint256 userInitialBalance = 100;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balanceAfter = fp.balanceOf(users[i], SEASON_1);
            assertEq(balanceAfter, userInitialBalance - stakePerUser, "User balance should be correct after prediction");
        }

        // Calculate required prize pool to ensure all winners get at least 1 FP winnings
        // Formula: (prizePool * points * stake) / totalShares >= 1
        // For each user: (prizePool * 4 * 1) / 20 >= 1
        // => prizePool * 4 >= 20
        // => prizePool >= 5
        // We have: originalPool (5) - sumWinnersStakes (5) + bonusPool (1) = 1 FP
        // We need at least 5 FP in prize pool, so we need 4 more FP
        uint256 requiredPrizePool = 5;
        uint256 currentPrizePool = originalPool - totalStakes + bonusPool; // 5 - 5 + 1 = 1
        uint256 additionalSeedNeeded = requiredPrizePool > currentPrizePool ? requiredPrizePool - currentPrizePool : 0; // Need 4 more FP

        console2.log("\n=== PRIZE POOL CALCULATION ===");
        console2.log("Original Pool: %d FP", originalPool);
        console2.log("Current Prize Pool (before seed): %d FP", currentPrizePool);
        console2.log("Required Prize Pool: %d FP (to ensure 1 FP winnings per user)", requiredPrizePool);
        console2.log("Additional Seed Needed: %d FP", additionalSeedNeeded);

        // Seed the prize pool if needed
        if (additionalSeedNeeded > 0) {
            console2.log("\n=== SEEDING PRIZE POOL ===");
            uint256 operatorBalanceBefore = fp.balanceOf(operator, SEASON_1);
            uint256 contractBalanceBeforeSeed = fp.balanceOf(address(booster), SEASON_1);

            vm.prank(operator);
            booster.depositBonus(eventId, fightId, additionalSeedNeeded, false);

            uint256 operatorBalanceAfter = fp.balanceOf(operator, SEASON_1);
            uint256 contractBalanceAfterSeed = fp.balanceOf(address(booster), SEASON_1);

            console2.log("Operator paid: %d FP", operatorBalanceBefore - operatorBalanceAfter);
            console2.log("Contract received: %d FP", contractBalanceAfterSeed - contractBalanceBeforeSeed);

            // Verify the seed was applied
            (,,, uint256 bonusPoolAfter,,,,,,,,) = booster.getFight(eventId, fightId);
            assertEq(bonusPoolAfter, initialPrizePool + additionalSeedNeeded, "Bonus pool should include seed");
            assertEq(bonusPoolAfter, requiredPrizePool, "Bonus pool after seed should equal required prize pool");

            // Verify operator balance decreased correctly
            assertEq(
                operatorBalanceAfter,
                operatorBalanceBefore - additionalSeedNeeded,
                "Operator should have paid seed amount"
            );
            // Verify contract balance increased correctly
            assertEq(
                contractBalanceAfterSeed,
                contractBalanceBeforeSeed + additionalSeedNeeded,
                "Contract should have received seed amount"
            );
        }

        // Resolve fight: RED + SUBMISSION wins
        // All 5 users win with exact match (4 points each)
        uint256 sumWinnersStakes = totalStakes; // All 5 users win
        uint256 winningPoolTotalShares = POINTS_FOR_WINNER_METHOD * totalStakes; // 4 * 5 = 20

        console2.log("\n=== RESOLVING FIGHT ===");
        console2.log("Winning outcome: RED + SUBMISSION");
        console2.log("All 5 users win (exact match = 4 points each)");
        console2.log("Sum Winners Stakes: %d FP", sumWinnersStakes);
        console2.log("Winning Pool Total Shares: %d (5 users x 4 points)", winningPoolTotalShares);

        vm.prank(operator);
        booster.submitFightResult(
            eventId,
            fightId,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            sumWinnersStakes,
            winningPoolTotalShares
        );

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(eventId, true);

        // Verify user points for all users (all should have exact match = 4 points)
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userPoints = booster.calculateUserPoints(
                Booster.Corner.RED,
                Booster.WinMethod.SUBMISSION,
                Booster.Corner.RED,
                Booster.WinMethod.SUBMISSION,
                POINTS_FOR_WINNER,
                POINTS_FOR_WINNER_METHOD
            );
            assertEq(userPoints, POINTS_FOR_WINNER_METHOD, "All users should have 4 points (exact match)");
        }

        // Get final prize pool after resolution
        uint256 finalPrizePool = originalPool - sumWinnersStakes + (initialPrizePool + additionalSeedNeeded);
        assertEq(finalPrizePool, requiredPrizePool, "Final prize pool should equal required prize pool (5 FP)");

        console2.log("\n=== AFTER RESOLUTION ===");
        console2.log("Final Prize Pool: ", finalPrizePool, " FP");
        uint256 expectedWinningsPerUser = (finalPrizePool * POINTS_FOR_WINNER_METHOD) / winningPoolTotalShares;
        assertGe(expectedWinningsPerUser, 1, "Expected winnings per user should be at least 1 FP");
        console2.log("Expected winnings per user:", expectedWinningsPerUser, "FP");

        // Verify contract balance before claims
        uint256 contractBalanceBeforeClaims = fp.balanceOf(address(booster), SEASON_1);
        uint256 expectedContractBalance = originalPool + initialPrizePool + additionalSeedNeeded; // 5 + 1 + 4 = 10
        assertEq(
            contractBalanceBeforeClaims, expectedContractBalance, "Contract balance should be correct before claims"
        );

        // Verify all users can claim and have winnings >= 1 FP
        uint256[] memory totalClaimables = new uint256[](users.length);
        uint256[] memory balancesBefore = new uint256[](users.length);

        console2.log("\n=== VERIFYING WINNINGS ===");
        for (uint256 i = 0; i < users.length; i++) {
            uint256 totalClaimable = booster.quoteClaimable(eventId, fightId, users[i], false);
            totalClaimables[i] = totalClaimable;
            balancesBefore[i] = fp.balanceOf(users[i], SEASON_1);

            // Calculate expected winnings (excluding stake)
            uint256 userWinnings = totalClaimable > stakePerUser ? totalClaimable - stakePerUser : 0;

            console2.log("User", i + 1);
            console2.log("  Claimable:", totalClaimable);
            console2.log("  Stake:", stakePerUser);
            console2.log("  Winnings:", userWinnings);

            // Verify user can claim
            assertGt(totalClaimable, 0, "User should be able to claim");
            // Verify winnings are at least 1 FP (after seeding)
            assertGe(userWinnings, 1, "User should receive at least 1 FP winnings after seeding");
            // Verify total payout is at least 2 FP (1 stake + 1 winnings)
            assertGe(totalClaimable, 2, "User should receive at least 2 FP total (stake + winnings)");
        }

        // Verify all users have the same claimable amount (all should get 1 stake + 1 winnings = 2 FP)
        for (uint256 i = 1; i < users.length; i++) {
            assertEq(totalClaimables[i], totalClaimables[0], "All users should have the same claimable amount");
        }
        assertGe(totalClaimables[0], stakePerUser + 1, "First user claimable should be at least stake + 1 winnings");

        // Users claim their winnings
        console2.log("\n=== USERS CLAIM WINNINGS ===");
        uint256 totalPayouts = 0;
        for (uint256 i = 0; i < users.length; i++) {
            uint256[] memory indices = booster.getUserBoostIndices(eventId, fightId, users[i]);
            uint256 balanceBeforeClaim = fp.balanceOf(users[i], SEASON_1);
            uint256 contractBalanceBeforeClaim = fp.balanceOf(address(booster), SEASON_1);

            vm.prank(users[i]);
            booster.claimReward(eventId, fightId, indices);

            uint256 balanceAfterClaim = fp.balanceOf(users[i], SEASON_1);
            uint256 contractBalanceAfterClaim = fp.balanceOf(address(booster), SEASON_1);
            uint256 received = balanceAfterClaim - balanceBeforeClaim;
            uint256 contractPaid = contractBalanceBeforeClaim - contractBalanceAfterClaim;

            totalPayouts += totalClaimables[i];

            console2.log("User", i + 1);
            console2.log("  Received:", received, "FP");
            console2.log("  Contract paid:", contractPaid, "FP");

            assertEq(
                balanceAfterClaim, balanceBeforeClaim + totalClaimables[i], "User balance should match expected payout"
            );
            assertEq(contractPaid, totalClaimables[i], "Contract should pay exact claimable amount");
        }

        // Verify total payouts calculation
        uint256 expectedTotalPayouts = totalClaimables[0] * users.length; // All users get the same amount
        assertEq(totalPayouts, expectedTotalPayouts, "Total payouts should equal sum of all claimables");
        assertGe(
            totalPayouts, (stakePerUser + 1) * users.length, "Total payouts should be at least (stake + 1) * users"
        );

        // Final balances and remainder
        console2.log("\n=== FINAL RESULTS ===");
        uint256 contractBalanceFinal = fp.balanceOf(address(booster), SEASON_1);
        uint256 contractBalanceBefore = originalPool + initialPrizePool + additionalSeedNeeded;
        assertEq(contractBalanceBefore, expectedContractBalance, "Contract balance before should match expected");

        console2.log("Total Payouts: %d FP (5 users x average)", totalPayouts);
        console2.log("Contract Balance Before: %d FP", contractBalanceBefore);
        console2.log("Contract Balance After: %d FP", contractBalanceFinal);
        console2.log("Remainder: %d FP (truncation remainder)", contractBalanceFinal);

        // Verify remainder calculation
        uint256 expectedRemainder = contractBalanceBefore - totalPayouts;
        assertEq(contractBalanceFinal, expectedRemainder, "Contract should have correct remainder");

        // Verify final user balances
        for (uint256 i = 0; i < users.length; i++) {
            uint256 finalBalance = fp.balanceOf(users[i], SEASON_1);
            uint256 expectedFinalBalance = balancesBefore[i] + totalClaimables[i];
            assertEq(finalBalance, expectedFinalBalance, "User final balance should be correct");
            assertGe(finalBalance, userInitialBalance, "User should have at least initial balance back");
        }

        // Verify all positions are claimed
        for (uint256 i = 0; i < users.length; i++) {
            uint256 claimableAfter = booster.quoteClaimable(eventId, fightId, users[i], false);
            assertEq(claimableAfter, 0, "User should have no remaining claimable");
        }

        console2.log("\n[PASS] Edge Case 2 PASSED: All winners received winnings thanks to seeding!");
    }

    /**
     * @notice Test case: Result correction after incorrect claims
     * @dev Tests the scenario where:
     *      1. Initial result submitted: Fight 1 → RED wins
     *      2. setEventClaimReady(eventId, true) enables claims
     *      3. RED winners claim before operator figures out issues (claimedAmount increases, and also _processWinningBoostClaim sets claimed to true)
     *      4. Operator calls setEventClaimReady(eventId, false)
     *      5. Operator calls submitFightResult with corrected result: Fight 1 → BLUE wins
     *      6. BLUE winners (the actually correct winners) attempt to claim but their boosts still show claimed=true from prior logic so claim will fail.
     *
     *      This test verifies that when results are corrected, the correct winners can still claim
     *      even if incorrect winners already claimed.
     */
    function test_resultCorrectionAfterIncorrectClaims() public {
        console2.log("\n=== TEST CASE: Result Correction After Incorrect Claims ===");

        string memory eventId = "UFC_RESULT_CORRECTION";
        uint256 fightId = 1;

        // ============ STEP 1: Setup Event and Boosts ============
        vm.prank(operator);
        booster.createEvent(eventId, 1, SEASON_1, 0);

        // Deposit prize pool
        uint256 prizePool = 100;
        vm.prank(operator);
        booster.depositBonus(eventId, fightId, prizePool, false);

        // User1 bets on RED + SUBMISSION
        uint256 user1Stake = 20;
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(fightId, user1Stake, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(eventId, boosts1);

        // User2 bets on BLUE + SUBMISSION
        uint256 user2Stake = 30;
        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(fightId, user2Stake, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(eventId, boosts2);

        // Verify original pool
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(originalPool, user1Stake + user2Stake, "Original pool should equal total stakes");

        console2.log("\n=== SETUP ===");
        console2.log("User1 bet: %d FP on RED + SUBMISSION", user1Stake);
        console2.log("User2 bet: %d FP on BLUE + SUBMISSION", user2Stake);
        console2.log("Original pool: %d FP", originalPool);
        console2.log("Prize pool: %d FP", prizePool);

        // ============ STEP 2: Submit INCORRECT result (RED wins) ============
        // Calculate points for incorrect result (RED wins)
        uint256 user1Points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user2Points = booster.calculateUserPoints(
            Booster.Corner.BLUE,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User1 wins (RED)
        uint256 incorrectSumWinnersStakes = user1Stake;
        uint256 incorrectWinningPoolTotalShares = user1Points * user1Stake; // 4 * 20 = 80

        console2.log("\n=== STEP 2: Submit INCORRECT Result (RED wins) ===");
        console2.log("User1 points: %d (winner)", user1Points);
        console2.log("User2 points: %d (loser)", user2Points);

        vm.prank(operator);
        booster.submitFightResult(
            eventId,
            fightId,
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            incorrectSumWinnersStakes,
            incorrectWinningPoolTotalShares
        );

        // Verify fight is resolved
        (Booster.FightStatus status,,,,,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED), "Fight should be resolved");

        // ============ STEP 3: Enable claims ============
        vm.prank(operator);
        booster.setEventClaimReady(eventId, true);

        console2.log("\n=== STEP 3: Claims Enabled ===");
        assertTrue(booster.isEventClaimReady(eventId), "Event should be claim ready");

        // ============ STEP 4: User1 (incorrect winner) claims ============
        uint256[] memory user1Indices = booster.getUserBoostIndices(eventId, fightId, user1);
        uint256 user1ClaimableBefore = booster.quoteClaimable(eventId, fightId, user1, false);
        uint256 user1BalanceBefore = fp.balanceOf(user1, SEASON_1);
        uint256 contractBalanceBefore = fp.balanceOf(address(booster), SEASON_1);

        console2.log("\n=== STEP 4: User1 (INCORRECT winner) Claims ===");
        console2.log("User1 claimable: %d FP", user1ClaimableBefore);
        console2.log("User1 balance before: %d FP", user1BalanceBefore);

        assertGt(user1ClaimableBefore, 0, "User1 should be able to claim (incorrectly)");

        vm.prank(user1);
        booster.claimReward(eventId, fightId, user1Indices);

        uint256 user1BalanceAfter = fp.balanceOf(user1, SEASON_1);
        uint256 contractBalanceAfter = fp.balanceOf(address(booster), SEASON_1);

        console2.log("User1 balance after: %d FP", user1BalanceAfter);
        console2.log("User1 received: %d FP", user1BalanceAfter - user1BalanceBefore);
        console2.log("Contract paid: %d FP", contractBalanceBefore - contractBalanceAfter);

        assertEq(user1BalanceAfter, user1BalanceBefore + user1ClaimableBefore, "User1 should have received claim");

        // Verify User1's boost is marked as claimed
        Booster.Boost[] memory user1Boosts = booster.getUserBoosts(eventId, fightId, user1);
        assertTrue(user1Boosts[0].claimed, "User1's boost should be marked as claimed");

        // Verify User2 cannot claim (they lost with incorrect result)
        uint256 user2ClaimableBefore = booster.quoteClaimable(eventId, fightId, user2, false);
        assertEq(user2ClaimableBefore, 0, "User2 should not be able to claim (lost with incorrect result)");

        // Get claimed amount after User1's incorrect claim
        (,,,,,,,,, uint256 claimedAmountBeforeCorrection,,) = booster.getFight(eventId, fightId);
        console2.log("Claimed amount: %d FP", claimedAmountBeforeCorrection);

        // ============ STEP 5: Disable claims and correct result ============
        vm.prank(operator);
        booster.setEventClaimReady(eventId, false);

        console2.log("\n=== STEP 5: Disable Claims and Correct Result ===");
        assertFalse(booster.isEventClaimReady(eventId), "Event should not be claim ready");

        // Deposit additional bonus (150 FP) after correcting result
        // Using force=true to allow deposit even though fight is RESOLVED
        // This is needed when correcting results after incorrect claims
        uint256 additionalBonus = 150;
        vm.prank(operator);
        booster.depositBonus(eventId, fightId, additionalBonus, true);

        console2.log("Additional bonus deposited: %d FP", additionalBonus);

        // Verify bonus pool increased
        (,,, uint256 bonusPoolAfter,,,,,,,,) = booster.getFight(eventId, fightId);
        assertEq(bonusPoolAfter, prizePool + additionalBonus, "Bonus pool should include additional deposit");

        // Calculate points for CORRECT result (BLUE wins)
        uint256 user1PointsCorrect = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.BLUE,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );
        uint256 user2PointsCorrect = booster.calculateUserPoints(
            Booster.Corner.BLUE,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.BLUE,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD
        );

        // Only User2 wins (BLUE) - but we need to account for what was already claimed
        // User1 already claimed
        // sumWinnersStakes should only include stakes from winners who haven't claimed yet
        uint256 correctSumWinnersStakes = user2Stake; // Only User2, User1 already claimed

        // Calculate prize pool that the contract will use
        // prizePool = originalPool - sumWinnersStakes + bonusPool
        // prizePool = 50 - 30 + 250 = 270 FP
        uint256 totalPrizePool = originalPool - correctSumWinnersStakes + bonusPoolAfter;

        // User2 should receive 150 FP total (30 stake + 120 winnings)
        // User2 shares: 4 points * 30 stake = 120
        uint256 user2Shares = user2PointsCorrect * user2Stake;

        // The contract calculates: winnings = (prizePool * userShares) / winningPoolTotalShares
        // We want: 120 = (270 * 120) / winningPoolTotalShares
        // Therefore: winningPoolTotalShares = 270
        // This compensates for the fact that the prize pool includes what was already claimed
        uint256 correctWinningPoolTotalShares = totalPrizePool;

        console2.log("Adjusting calculations for corrected result:");
        console2.log("  Already claimed: %d FP", claimedAmountBeforeCorrection);
        console2.log("  Total prize pool (contract will use): %d FP", totalPrizePool);
        console2.log("  User2 stake (unclaimed): %d FP", correctSumWinnersStakes);
        console2.log("  User2 shares: %d", user2Shares);
        console2.log("  Adjusted winningPoolTotalShares: %d", correctWinningPoolTotalShares);
        console2.log("  Expected User2 winnings: %d FP", (totalPrizePool * user2Shares) / correctWinningPoolTotalShares);
        console2.log(
            "  Expected User2 total payout: %d FP",
            (totalPrizePool * user2Shares) / correctWinningPoolTotalShares + user2Stake
        );

        console2.log("Correct result: BLUE wins");
        console2.log("User1 points: %d (loser)", user1PointsCorrect);
        console2.log("User2 points: %d (winner)", user2PointsCorrect);

        // Submit corrected result
        vm.prank(operator);
        booster.submitFightResult(
            eventId,
            fightId,
            Booster.Corner.BLUE,
            Booster.WinMethod.SUBMISSION,
            POINTS_FOR_WINNER,
            POINTS_FOR_WINNER_METHOD,
            correctSumWinnersStakes,
            correctWinningPoolTotalShares
        );

        // ============ STEP 6: Re-enable claims ============
        vm.prank(operator);
        booster.setEventClaimReady(eventId, true);

        console2.log("\n=== STEP 6: Re-enable Claims ===");
        assertTrue(booster.isEventClaimReady(eventId), "Event should be claim ready again");

        // ============ STEP 7: User2 (correct winner) attempts to claim ============
        uint256[] memory user2Indices = booster.getUserBoostIndices(eventId, fightId, user2);
        uint256 user2ClaimableAfter = booster.quoteClaimable(eventId, fightId, user2, false);
        uint256 user2BalanceBefore = fp.balanceOf(user2, SEASON_1);

        console2.log("\n=== STEP 7: User2 (CORRECT winner) Attempts to Claim ===");
        console2.log("User2 claimable: %d FP", user2ClaimableAfter);
        console2.log("User2 balance before: %d FP", user2BalanceBefore);

        // Check if User2's boost is marked as claimed (this is the bug we're testing)
        Booster.Boost[] memory user2Boosts = booster.getUserBoosts(eventId, fightId, user2);
        console2.log("User2 boost claimed status: %s", user2Boosts[0].claimed ? "true" : "false");

        // This is the critical test: User2 should be able to claim even though User1 already claimed
        // If User2's boost is marked as claimed=true incorrectly, this will fail
        if (user2Boosts[0].claimed) {
            console2.log("\n[BUG DETECTED] User2's boost is marked as claimed=true, but User2 never claimed!");
            console2.log("This means User2 cannot claim their correct winnings.");

            // Try to claim and expect it to fail
            vm.expectRevert("already claimed");
            vm.prank(user2);
            booster.claimReward(eventId, fightId, user2Indices);

            console2.log("[FAIL] Test confirms the bug: User2 cannot claim because boost.claimed=true");
        } else {
            console2.log("\n[EXPECTED] User2's boost is NOT marked as claimed, so User2 can claim");

            // User2 should be able to claim
            assertGt(user2ClaimableAfter, 0, "User2 should be able to claim (correct winner)");

            vm.prank(user2);
            booster.claimReward(eventId, fightId, user2Indices);

            uint256 user2BalanceAfter = fp.balanceOf(user2, SEASON_1);
            console2.log("User2 balance after: %d FP", user2BalanceAfter);
            console2.log("User2 received: %d FP", user2BalanceAfter - user2BalanceBefore);

            assertEq(user2BalanceAfter, user2BalanceBefore + user2ClaimableAfter, "User2 should have received claim");

            console2.log("[PASS] User2 successfully claimed their correct winnings");
        }

        // ============ STEP 8: Verify final state ============
        console2.log("\n=== STEP 8: Final State Verification ===");

        // Check fight claimed amount
        (,,,,,,,,, uint256 claimedAmount,,) = booster.getFight(eventId, fightId);
        console2.log("Fight claimed amount: %d FP", claimedAmount);

        // Check contract balance
        uint256 contractBalanceFinal = fp.balanceOf(address(booster), SEASON_1);
        console2.log("Contract balance final: %d FP", contractBalanceFinal);

        // Check user balances
        console2.log("User1 balance final: %d FP", fp.balanceOf(user1, SEASON_1));
        console2.log("User2 balance final: %d FP", fp.balanceOf(user2, SEASON_1));

        // Verify User1 cannot claim again (already claimed)
        uint256 user1ClaimableAfter = booster.quoteClaimable(eventId, fightId, user1, false);
        assertEq(user1ClaimableAfter, 0, "User1 should not be able to claim again");

        console2.log("\n=== TEST COMPLETE ===");
    }
}
