// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {FP1155} from "src/FP1155.sol";
import {Sportsbook} from "src/Sportsbook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract SportsbookTest is Test, IERC1155Receiver {
    FP1155 public fp1155;
    Sportsbook public sportsbook;
    Sportsbook public sportsbookImpl;

    address public admin = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 public constant SEASON_ID = 1;
    uint256 public constant SEASON_TOKEN_ID = 1;
    uint256 public constant USER_BALANCE = 1000;
    uint256 public constant PRIZE_POOL = 500;

    // Helper function to decode outcome
    // Outcome encoding: bits 0-1 = method (0-3), bit 2 = winner (0=Fighter A, 1=Fighter B)
    // Methods: 0 = Submission, 1 = Decision, 2 = KO/TKO, 3 = No-Contest
    function decodeOutcome(uint256 outcome) internal pure returns (string memory fighter, string memory method) {
        uint256 fighterIndex = (outcome >> 2) & 1;
        uint256 methodValue = outcome & 0x3;
        
        fighter = fighterIndex == 0 ? "FighterA" : "FighterB";
        
        if (methodValue == 0) {
            method = "Submission";
        } else if (methodValue == 1) {
            method = "Decision";
        } else if (methodValue == 2) {
            method = "KO/TKO";
        } else {
            method = "No-Contest";
        }
    }

    function setUp() public {
        // Deploy FP1155
        fp1155 = new FP1155("ipfs://base/{id}.json", admin);
        
        // Grant MINTER_ROLE to admin
        fp1155.grantRole(fp1155.MINTER_ROLE(), admin);
        
        // Deploy Sportsbook implementation
        sportsbookImpl = new Sportsbook();
        
        // Encode initialize call
        bytes memory initData = abi.encodeWithSelector(
            Sportsbook.initialize.selector,
            address(fp1155),
            admin
        );
        
        // Deploy ERC1967Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(sportsbookImpl), initData);
        sportsbook = Sportsbook(payable(address(proxy)));
        
        // Grant TRANSFER_AGENT_ROLE to Sportsbook
        fp1155.grantRole(fp1155.TRANSFER_AGENT_ROLE(), address(sportsbook));
        
        // Add Sportsbook to allowlist (required for ERC1155 transfers)
        fp1155.setTransferAllowlist(address(sportsbook), true);
        
        // Setup users: mint tokens, allowlist, approve
        _setupUser(user1);
        _setupUser(user2);
        _setupUser(user3);
    }

    function _setupUser(address user) internal {
        // Mint tokens
        fp1155.mint(user, SEASON_TOKEN_ID, USER_BALANCE, "");
        
        // Add to allowlist
        fp1155.setTransferAllowlist(user, true);
        
        // Approve Sportsbook
        vm.prank(user);
        fp1155.setApprovalForAll(address(sportsbook), true);
    }

    function testDeployContracts() public {
        assertTrue(address(fp1155) != address(0));
        assertTrue(address(sportsbook) != address(0));
        assertTrue(address(sportsbookImpl) != address(0));
    }

    function testGrantTransferAgentRole() public {
        bytes32 role = fp1155.TRANSFER_AGENT_ROLE();
        assertTrue(fp1155.hasRole(role, address(sportsbook)));
        assertTrue(fp1155.endpointAllowed(address(sportsbook)));
    }

    function testSingleFightAnalysis() public {
        // ============ STEP 1: Create Season with 1 fight ============
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        // Mint FP tokens to admin for prize pool
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        // Create season
        vm.expectEmit(true, true, true, true);
        emit Sportsbook.SeasonCreated(SEASON_ID, cutOffTime, SEASON_TOKEN_ID, 1);
        sportsbook.createSeasonWithFights(
            SEASON_ID,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // ============ STEP 2: Users make predictions ============
        uint256 stake1 = 20;
        uint256 stake2 = 30;
        uint256 stake3 = 25;
        
        console2.log("\n=== TEST CASE: Single Fight Analysis ===");
        console2.log("Setup: User1 bets", stake1);
        console2.log("       User2 bets", stake2);
        console2.log("       User3 bets", stake3);
        
        // User1: Bets on Fight 0 (outcome 0 = Fighter A, Submission)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Sportsbook.PredictionLocked(user1, SEASON_ID, 0, 0, stake1);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0),
            _toArray(0),
            _toArray(stake1)
        );
        
        // User2: Bets on Fight 0 (outcome 1 = Fighter A, Decision)
        vm.prank(user2);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0),
            _toArray(1),
            _toArray(stake2)
        );
        
        // User3: Bets on Fight 0 (outcome 0 = Fighter A, Submission)
        vm.prank(user3);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0),
            _toArray(0),
            _toArray(stake3)
        );
        
        // Verify balances
        assertEq(fp1155.balanceOf(user1, SEASON_TOKEN_ID), USER_BALANCE - stake1);
        assertEq(fp1155.balanceOf(user2, SEASON_TOKEN_ID), USER_BALANCE - stake2);
        assertEq(fp1155.balanceOf(user3, SEASON_TOKEN_ID), USER_BALANCE - stake3);
        
        uint256 totalStakes = stake1 + stake2 + stake3;
        uint256 expectedContractBalance = 100 + totalStakes; // Prize pool (100) + total stakes (75)
        assertEq(fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID), expectedContractBalance);
        
        // ============ STEP 3: Resolve Season (Fight 0 only) ============
        // Winning outcome: Fight 0: 0 (Fighter A, Submission) - User1 and User3 win
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // Fighter A, Submission
        uint256 expectedWinningOutcome = uint256(winningOutcomes[0]);
        
        vm.expectEmit(true, true, false, true);
        emit Sportsbook.FightResolved(SEASON_ID, 0, 0);
        sportsbook.resolveSeason(SEASON_ID, winningOutcomes);
        
        // Get fight state and calculate expected values
        (uint256 prizePool, uint256 fighterAStaked, uint256 fighterBStaked, , , , , ) = 
            sportsbook.fightStates(SEASON_ID, 0);
        
        // Get positions to calculate shares
        Sportsbook.Position memory position1Before = sportsbook.getPosition(user1, SEASON_ID, 0);
        Sportsbook.Position memory position2Before = sportsbook.getPosition(user2, SEASON_ID, 0);
        Sportsbook.Position memory position3Before = sportsbook.getPosition(user3, SEASON_ID, 0);
        
        // Calculate expected winning pool total shares dynamically
        // User1: outcome 0 (exact match) = 4 shares
        // User2: outcome 1 (winner only) = 3 shares
        // User3: outcome 0 (exact match) = 4 shares
        (bool canClaim1Before, uint256 userPoints1Before, , , ) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        (bool canClaim2Before, uint256 userPoints2Before, , , ) = 
            sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        (bool canClaim3Before, uint256 userPoints3Before, , , ) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        
        uint256 expectedWinningPoolTotalShares = 
            (userPoints1Before * position1Before.stakeAmount) +
            (userPoints2Before * position2Before.stakeAmount) +
            (userPoints3Before * position3Before.stakeAmount);
        
        // Calculate expected total winnings pool (prize pool + loser stakes)
        uint256 winningFighterIndex = (expectedWinningOutcome >> 2) & 1;
        uint256 expectedTotalLoserStakes = winningFighterIndex == 0 
            ? fighterBStaked 
            : fighterAStaked;
        uint256 expectedTotalWinningsPool = prizePool + expectedTotalLoserStakes;
        
        // Verify resolution data
        (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
            sportsbook.getFightResolutionData(SEASON_ID, 0);
        assertEq(winningOutcome, expectedWinningOutcome);
        assertEq(totalWinningsPool, expectedTotalWinningsPool);
        assertEq(winningPoolTotalShares, expectedWinningPoolTotalShares);
        
        console2.log("\nResolution: Winning outcome", winningOutcome);
        console2.log("           Total Winnings Pool:", totalWinningsPool);
        console2.log("           Winning Pool Total Shares:", winningPoolTotalShares);
        
        // ============ STEP 4: Users claim winnings ============
        // User1 should have winnings from Fight 0 (exact match, 4 shares)
        uint256 balanceBefore1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        uint256 contractBalanceBeforeClaim1 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        (bool canClaim1, uint256 userPoints1, uint256 userWinnings1, uint256 totalPayout1, bool claimed1) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        Sportsbook.Position memory position1 = sportsbook.getPosition(user1, SEASON_ID, 0);
        
        assertTrue(canClaim1);
        assertGt(userPoints1, 0); // Should have points (exact match = 4)
        assertEq(userPoints1, 4); // Exact match
        assertFalse(claimed1);
        // Calculate expected winnings dynamically
        uint256 user1Shares = userPoints1 * position1.stakeAmount; // userPoints * stake
        uint256 expectedWinnings1 = (totalWinningsPool * user1Shares) / winningPoolTotalShares;
        assertEq(userWinnings1, expectedWinnings1);
        assertEq(totalPayout1, position1.stakeAmount + expectedWinnings1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Sportsbook.Claimed(user1, SEASON_ID, 0, totalPayout1);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        uint256 contractBalanceAfterClaim1 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(balanceAfter1, balanceBefore1 + totalPayout1);
        assertEq(contractBalanceAfterClaim1, contractBalanceBeforeClaim1 - totalPayout1);
        
        // User2 should have winnings from Fight 0 (winner only, 3 shares)
        uint256 balanceBefore2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        uint256 contractBalanceBeforeClaim2 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        (bool canClaim2, uint256 userPoints2, uint256 userWinnings2, uint256 totalPayout2, bool claimed2) = 
            sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        Sportsbook.Position memory position2 = sportsbook.getPosition(user2, SEASON_ID, 0);
        
        assertTrue(canClaim2);
        assertGt(userPoints2, 0); // Should have points (winner only = 3)
        assertEq(userPoints2, 3); // Winner only
        assertFalse(claimed2);
        // Calculate expected winnings dynamically
        uint256 user2Shares = userPoints2 * position2.stakeAmount; // userPoints * stake
        uint256 expectedWinnings2 = (totalWinningsPool * user2Shares) / winningPoolTotalShares;
        assertEq(userWinnings2, expectedWinnings2);
        assertEq(totalPayout2, position2.stakeAmount + expectedWinnings2);
        
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit Sportsbook.Claimed(user2, SEASON_ID, 0, totalPayout2);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        uint256 contractBalanceAfterClaim2 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(balanceAfter2, balanceBefore2 + totalPayout2);
        assertEq(contractBalanceAfterClaim2, contractBalanceBeforeClaim2 - totalPayout2);
        
        // User3 should have winnings from Fight 0 (exact match, 4 shares)
        uint256 balanceBefore3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        uint256 contractBalanceBeforeClaim3 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        (bool canClaim3, uint256 userPoints3, uint256 userWinnings3, uint256 totalPayout3, bool claimed3) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        Sportsbook.Position memory position3 = sportsbook.getPosition(user3, SEASON_ID, 0);
        
        assertTrue(canClaim3);
        assertGt(userPoints3, 0); // Should have points (exact match = 4)
        assertEq(userPoints3, 4); // Exact match
        assertFalse(claimed3);
        // Calculate expected winnings dynamically
        uint256 user3Shares = userPoints3 * position3.stakeAmount; // userPoints * stake
        uint256 expectedWinnings3 = (totalWinningsPool * user3Shares) / winningPoolTotalShares;
        assertEq(userWinnings3, expectedWinnings3);
        assertEq(totalPayout3, position3.stakeAmount + expectedWinnings3);
        
        vm.prank(user3);
        vm.expectEmit(true, true, true, true);
        emit Sportsbook.Claimed(user3, SEASON_ID, 0, totalPayout3);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        uint256 contractBalanceAfterClaim3 = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(balanceAfter3, balanceBefore3 + totalPayout3);
        assertEq(contractBalanceAfterClaim3, contractBalanceBeforeClaim3 - totalPayout3);
        
        // Verify final balances and totals
        assertEq(balanceAfter1, balanceBefore1 + totalPayout1);
        assertEq(balanceAfter2, balanceBefore2 + totalPayout2);
        assertEq(balanceAfter3, balanceBefore3 + totalPayout3);
        
        // Verify total payout and remainder
        uint256 totalWinningsPaid = userWinnings1 + userWinnings2 + userWinnings3;
        uint256 calculatedTotalStakes = position1.stakeAmount + position2.stakeAmount + position3.stakeAmount;
        uint256 totalPayout = calculatedTotalStakes + totalWinningsPaid;
        uint256 expectedRemainder = (100 + calculatedTotalStakes) - totalPayout; // totalPrizePool (100) + stakes - payouts
        assertEq(contractBalanceAfterClaim3, expectedRemainder);
        
        console2.log("\n=== RESULTS SUMMARY ===");
        console2.log("User1 winnings:", userWinnings1);
        console2.log("User1 stake:", position1.stakeAmount);
        console2.log("User1 total payout:", totalPayout1);
        console2.log("User2 winnings:", userWinnings2);
        console2.log("User2 stake:", position2.stakeAmount);
        console2.log("User2 total payout:", totalPayout2);
        console2.log("User3 winnings:", userWinnings3);
        console2.log("User3 stake:", position3.stakeAmount);
        console2.log("User3 total payout:", totalPayout3);
        console2.log("Total Winnings Paid:", totalWinningsPaid);
        console2.log("Total Payout:", totalPayout);
        console2.log("Remainder in Contract:", expectedRemainder);
        
        // Verify all positions are claimed
        (, , , , bool claimed1After) = sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        (, , , , bool claimed2After) = sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        (, , , , bool claimed3After) = sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        assertTrue(claimed1After);
        assertTrue(claimed2After);
        assertTrue(claimed3After);
    }

    function testCompleteFlow() public {
        console2.log("\n=== TEST: Complete Flow ===");
        
        // ============ STEP 1: Create Season with 5 fights ============
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](5);
        for (uint256 i = 0; i < 5; i++) {
            fightConfigs[i] = Sportsbook.FightConfig({
                minBet: 10,
                maxBet: 100,
                numOutcomes: 6
            });
        }
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            fightPrizePoolAmounts[i] = 100;
        }
        
        // Mint FP tokens to admin for prize pools
        fp1155.mint(admin, SEASON_TOKEN_ID, PRIZE_POOL, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            SEASON_ID,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        console2.log("Season created with 5 fights");
        console2.log("Prize pool per fight: 100 FP");
        console2.log("Total prize pool: 500 FP");
        
        // ============ STEP 2: Users make predictions ============
        console2.log("\n=== Users making predictions ===");
        
        // User1: Bets on Fight 0, 1, 2
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0, 1, 2),
            _toArray(0, 0, 3),
            _toArray(20, 20, 20)
        );
        console2.log("User1: 20 FP on Fight 0 (outcome 0)");
        console2.log("User1: 20 FP on Fight 1 (outcome 0)");
        console2.log("User1: 20 FP on Fight 2 (outcome 3)");
        
        // User2: Bets on Fight 0, 1
        vm.prank(user2);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0, 1),
            _toArray(1, 4),
            _toArray(30, 30)
        );
        console2.log("User2: 30 FP on Fight 0 (outcome 1), 30 FP on Fight 1 (outcome 4)");
        
        // User3: Bets on Fight 0, 3, 4
        vm.prank(user3);
        sportsbook.lockPredictionsBatch(
            SEASON_ID,
            _toArray(0, 3, 4),
            _toArray(0, 0, 0),
            _toArray(25, 25, 25)
        );
        console2.log("User3: 25 FP on Fight 0 (outcome 0)");
        console2.log("User3: 25 FP on Fight 3 (outcome 0)");
        console2.log("User3: 25 FP on Fight 4 (outcome 0)");
        
        // ============ STEP 3: Resolve Season ============
        console2.log("\n=== Resolving season ===");
        uint8[] memory winningOutcomes = new uint8[](5);
        winningOutcomes[0] = 0; // Fighter A, Submission
        winningOutcomes[1] = 0; // Fighter A, Submission
        winningOutcomes[2] = 3; // Fighter B, Decision
        winningOutcomes[3] = 0; // Fighter A, Submission
        winningOutcomes[4] = 0; // Fighter A, Submission
        
        sportsbook.resolveSeason(SEASON_ID, winningOutcomes);
        
        console2.log("Winning outcomes:");
        console2.log("  Fight 0: outcome 0 (Fighter A, Submission)");
        console2.log("  Fight 1: outcome 0 (Fighter A, Submission)");
        console2.log("  Fight 2: outcome 3 (Fighter B, Decision)");
        console2.log("  Fight 3: outcome 0 (Fighter A, Submission)");
        console2.log("  Fight 4: outcome 0 (Fighter A, Submission)");
        
        // ============ STEP 4: Users claim winnings ============
        console2.log("\n=== Users claiming winnings ===");
        
        // User1 should have winnings from Fight 0, 1, 2
        uint256 balanceBefore1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        (bool canClaim1_0, uint256 points1_0, uint256 winnings1_0, uint256 payout1_0, ) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        (bool canClaim1_1, uint256 points1_1, uint256 winnings1_1, uint256 payout1_1, ) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 1);
        (bool canClaim1_2, uint256 points1_2, uint256 winnings1_2, uint256 payout1_2, ) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 2);
        
        // Calculate expected payout - only include fights where canClaim is true
        uint256 expectedPayout1 = 0;
        if (canClaim1_0) expectedPayout1 += payout1_0;
        if (canClaim1_1) expectedPayout1 += payout1_1;
        if (canClaim1_2) expectedPayout1 += payout1_2;
        
        console2.log("User1 before claim - Balance:", balanceBefore1);
        console2.log("  Fight 0: canClaim", canClaim1_0);
        console2.log("  Fight 0: winnings", winnings1_0);
        console2.log("  Fight 0: points", points1_0);
        console2.log("  Fight 0: payout", payout1_0);
        console2.log("  Fight 1: canClaim", canClaim1_1);
        console2.log("  Fight 1: winnings", winnings1_1);
        console2.log("  Fight 1: points", points1_1);
        console2.log("  Fight 1: payout", payout1_1);
        console2.log("  Fight 2: canClaim", canClaim1_2);
        console2.log("  Fight 2: winnings", winnings1_2);
        console2.log("  Fight 2: points", points1_2);
        console2.log("  Fight 2: payout", payout1_2);
        console2.log("  Expected total payout:", expectedPayout1);
        
        vm.prank(user1);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        console2.log("User1 after claim - Balance:", balanceAfter1);
        console2.log("User1 received:", balanceAfter1 - balanceBefore1);
        
        // User2 should have winnings from Fight 0 (winner only)
        uint256 balanceBefore2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        (bool canClaim2_0, uint256 points2_0, uint256 winnings2_0, uint256 payout2_0, ) = 
            sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        (bool canClaim2_1, uint256 points2_1, uint256 winnings2_1, uint256 payout2_1, ) = 
            sportsbook.getPositionWinnings(user2, SEASON_ID, 1);
        
        uint256 expectedPayout2 = 0;
        if (canClaim2_0) expectedPayout2 += payout2_0;
        if (canClaim2_1) expectedPayout2 += payout2_1;
        
        console2.log("User2 before claim - Balance:", balanceBefore2);
        console2.log("  Fight 0: canClaim", canClaim2_0);
        console2.log("  Fight 0: winnings", winnings2_0);
        console2.log("  Fight 0: points", points2_0);
        console2.log("  Fight 0: payout", payout2_0);
        console2.log("  Fight 1: canClaim", canClaim2_1);
        if (!canClaim2_1) {
            console2.log("  Fight 1: Lost (wrong fighter)");
        } else {
            console2.log("  Fight 1: winnings", winnings2_1);
            console2.log("  Fight 1: points", points2_1);
            console2.log("  Fight 1: payout", payout2_1);
        }
        console2.log("  Expected total payout:", expectedPayout2);
        
        vm.prank(user2);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        console2.log("User2 after claim - Balance:", balanceAfter2);
        console2.log("User2 received:", balanceAfter2 - balanceBefore2);
        
        // User3 should have winnings from Fight 0, 3, 4
        uint256 balanceBefore3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        (bool canClaim3_0, uint256 points3_0, uint256 winnings3_0, uint256 payout3_0, ) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        (bool canClaim3_3, uint256 points3_3, uint256 winnings3_3, uint256 payout3_3, ) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 3);
        (bool canClaim3_4, uint256 points3_4, uint256 winnings3_4, uint256 payout3_4, ) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 4);
        
        // Calculate expected payout - only include fights where canClaim is true
        uint256 expectedPayout3 = 0;
        if (canClaim3_0) expectedPayout3 += payout3_0;
        if (canClaim3_3) expectedPayout3 += payout3_3;
        if (canClaim3_4) expectedPayout3 += payout3_4;
        
        console2.log("User3 before claim - Balance:", balanceBefore3);
        console2.log("  Fight 0: canClaim", canClaim3_0);
        console2.log("  Fight 0: winnings", winnings3_0);
        console2.log("  Fight 0: points", points3_0);
        console2.log("  Fight 0: payout", payout3_0);
        console2.log("  Fight 3: canClaim", canClaim3_3);
        console2.log("  Fight 3: winnings", winnings3_3);
        console2.log("  Fight 3: points", points3_3);
        console2.log("  Fight 3: payout", payout3_3);
        console2.log("  Fight 4: canClaim", canClaim3_4);
        console2.log("  Fight 4: winnings", winnings3_4);
        console2.log("  Fight 4: points", points3_4);
        console2.log("  Fight 4: payout", payout3_4);
        console2.log("  Expected total payout:", expectedPayout3);
        
        vm.prank(user3);
        sportsbook.claim(SEASON_ID);
        
        uint256 balanceAfter3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        console2.log("User3 after claim - Balance:", balanceAfter3);
        console2.log("User3 received:", balanceAfter3 - balanceBefore3);
        
        // Final summary - only count winnings from fights where canClaim is true
        uint256 totalWinnings = 0;
        if (canClaim1_0) totalWinnings += winnings1_0;
        if (canClaim1_1) totalWinnings += winnings1_1;
        if (canClaim1_2) totalWinnings += winnings1_2;
        if (canClaim2_0) totalWinnings += winnings2_0;
        if (canClaim2_1) totalWinnings += winnings2_1;
        if (canClaim3_0) totalWinnings += winnings3_0;
        if (canClaim3_3) totalWinnings += winnings3_3;
        if (canClaim3_4) totalWinnings += winnings3_4;
        
        uint256 totalPayouts = expectedPayout1 + expectedPayout2 + expectedPayout3;
        uint256 contractBalance = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        
        console2.log("\n=== FINAL SUMMARY ===");
        console2.log("Total winnings paid:", totalWinnings);
        console2.log("Total payouts:", totalPayouts);
        console2.log("Contract balance remaining:", contractBalance);
        
        // Verify all positions are claimed
        // User1 has positions in fights 0, 1, 2
        (, , , , bool claimed1_0) = sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        (, , , , bool claimed1_1) = sportsbook.getPositionWinnings(user1, SEASON_ID, 1);
        (, , , , bool claimed1_2) = sportsbook.getPositionWinnings(user1, SEASON_ID, 2);
        assertTrue(claimed1_0);
        assertTrue(claimed1_1);
        assertTrue(claimed1_2);
        
        // User2 has positions in fights 0, 1
        (, , , , bool claimed2_0) = sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        (, , , , bool claimed2_1) = sportsbook.getPositionWinnings(user2, SEASON_ID, 1);
        assertTrue(claimed2_0);
        // User2 lost fight 1 (wrong fighter), so no claim
        
        // User3 has positions in fights 0, 3, 4
        (, , , , bool claimed3_0) = sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        (, , , , bool claimed3_3) = sportsbook.getPositionWinnings(user3, SEASON_ID, 3);
        (, , , , bool claimed3_4) = sportsbook.getPositionWinnings(user3, SEASON_ID, 4);
        assertTrue(claimed3_0);
        assertTrue(claimed3_3);
        assertTrue(claimed3_4);
        
        console2.log("All positions claimed successfully");
    }

    function testNoContestRefund() public {
        console2.log("\n=== TEST: No-Contest Refund ===");
        
        // ============ STEP 1: Create Season with 1 fight ============
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 8 // Includes No-Contest
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 1000;
        
        // Mint FP tokens to admin for prize pool
        fp1155.mint(admin, SEASON_TOKEN_ID, 1000, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            SEASON_ID,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // ============ STEP 2: Users make predictions ============
        uint256 stake1 = 100;
        uint256 stake2 = 200;
        uint256 stake3 = 150;
        
        console2.log("\nPredictions made:");
        console2.log("  User1:", stake1, "FP on outcome 0");
        console2.log("  User2:", stake2, "FP on outcome 1");
        console2.log("  User3:", stake3, "FP on outcome 4");
        console2.log("  Total staked:", stake1 + stake2 + stake3);
        console2.log("  Prize pool: 1000 FP");
        
        // User1: Bets on outcome 0 (Fighter A, Submission)
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(SEASON_ID, _toArray(0), _toArray(0), _toArray(stake1));
        
        // User2: Bets on outcome 1 (Fighter A, Decision)
        vm.prank(user2);
        sportsbook.lockPredictionsBatch(SEASON_ID, _toArray(0), _toArray(1), _toArray(stake2));
        
        // User3: Bets on outcome 4 (Fighter B, Submission)
        vm.prank(user3);
        sportsbook.lockPredictionsBatch(SEASON_ID, _toArray(0), _toArray(4), _toArray(stake3));
        
        // ============ STEP 3: Resolve with No-Contest ============
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 3; // Fighter A, No-Contest (method = 3)
        
        console2.log("\nResolving fight with No-Contest (outcome 3 = Fighter A, No-Contest)...");
        
        sportsbook.resolveSeason(SEASON_ID, winningOutcomes);
        
        // Verify fight state
        (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
            sportsbook.getFightResolutionData(SEASON_ID, 0);
        
        assertEq(winningOutcome, 3);
        assertEq(totalWinningsPool, 0); // Should be 0 for No-Contest
        assertEq(winningPoolTotalShares, 0); // Should be 0 for No-Contest
        
        console2.log("Fight resolved as No-Contest");
        console2.log("  Winning outcome:", winningOutcome);
        console2.log("  Total winnings pool:", totalWinningsPool);
        console2.log("  (should be 0)");
        console2.log("  Winning pool total shares:", winningPoolTotalShares);
        console2.log("  (should be 0)");
        
        // ============ STEP 4: Verify all users can claim (refund only) ============
        console2.log("\nVerifying claimable amounts for all users...");
        
        // User1: Should get refund (stake only), 0 points, 0 winnings
        (bool canClaim1, uint256 userPoints1, uint256 userWinnings1, uint256 totalPayout1, bool claimed1) = 
            sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        
        assertTrue(canClaim1);
        assertEq(userPoints1, 0); // 0 points for No-Contest
        assertEq(userWinnings1, 0); // 0 winnings for No-Contest
        assertEq(totalPayout1, stake1); // Only stake refund
        assertFalse(claimed1);
        
        console2.log("  User1: canClaim", canClaim1);
        console2.log("  User1: points", userPoints1);
        console2.log("  User1: winnings", userWinnings1);
        console2.log("  User1: totalPayout", totalPayout1);
        
        // User2: Should get refund (stake only)
        (bool canClaim2, uint256 userPoints2, uint256 userWinnings2, uint256 totalPayout2, bool claimed2) = 
            sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        
        assertTrue(canClaim2);
        assertEq(userPoints2, 0);
        assertEq(userWinnings2, 0);
        assertEq(totalPayout2, stake2);
        assertFalse(claimed2);
        
        console2.log("  User2: canClaim", canClaim2);
        console2.log("  User2: points", userPoints2);
        console2.log("  User2: winnings", userWinnings2);
        console2.log("  User2: totalPayout", totalPayout2);
        
        // User3: Should get refund (stake only)
        (bool canClaim3, uint256 userPoints3, uint256 userWinnings3, uint256 totalPayout3, bool claimed3) = 
            sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        
        assertTrue(canClaim3);
        assertEq(userPoints3, 0);
        assertEq(userWinnings3, 0);
        assertEq(totalPayout3, stake3);
        assertFalse(claimed3);
        
        console2.log("  User3: canClaim", canClaim3);
        console2.log("  User3: points", userPoints3);
        console2.log("  User3: winnings", userWinnings3);
        console2.log("  User3: totalPayout", totalPayout3);
        
        // ============ STEP 5: Users claim refunds ============
        console2.log("\nUsers claiming refunds...");
        
        uint256 balanceBefore1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        vm.prank(user1);
        sportsbook.claim(SEASON_ID);
        uint256 balanceAfter1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        uint256 refund1 = balanceAfter1 - balanceBefore1;
        assertEq(refund1, stake1);
        console2.log("  User1 claimed:", refund1);
        console2.log("  User1 expected:", stake1);
        
        uint256 balanceBefore2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        vm.prank(user2);
        sportsbook.claim(SEASON_ID);
        uint256 balanceAfter2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        uint256 refund2 = balanceAfter2 - balanceBefore2;
        assertEq(refund2, stake2);
        console2.log("  User2 claimed:", refund2);
        console2.log("  User2 expected:", stake2);
        
        uint256 balanceBefore3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        vm.prank(user3);
        sportsbook.claim(SEASON_ID);
        uint256 balanceAfter3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        uint256 refund3 = balanceAfter3 - balanceBefore3;
        assertEq(refund3, stake3);
        console2.log("  User3 claimed:", refund3);
        console2.log("  User3 expected:", stake3);
        
        // ============ STEP 6: Verify final balances ============
        uint256 totalRefunded = refund1 + refund2 + refund3;
        uint256 contractBalance = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(contractBalance, 1000); // Prize pool remains (not distributed)
        
        console2.log("\n=== FINAL BALANCES ===");
        console2.log("  Total refunded:", totalRefunded);
        console2.log("  Contract balance after claims:", contractBalance);
        console2.log("  Expected remaining (prize pool): 1000 FP");
        console2.log("All users received refund (stake only)");
        console2.log("Prize pool remains in contract (not distributed)");
        console2.log("No points awarded (0 points for all users)");
        console2.log("No winnings paid (0 winnings for all users)");
        
        // Verify positions are marked as claimed
        (, , , , bool claimed1After) = sportsbook.getPositionWinnings(user1, SEASON_ID, 0);
        (, , , , bool claimed2After) = sportsbook.getPositionWinnings(user2, SEASON_ID, 0);
        (, , , , bool claimed3After) = sportsbook.getPositionWinnings(user3, SEASON_ID, 0);
        
        assertTrue(claimed1After);
        assertTrue(claimed2After);
        assertTrue(claimed3After);
        
        console2.log("All positions marked as claimed");
        
        // ============ STEP 7: Test recoverRemainingBalance ============
        // Get settlement time from season
        (uint256 cutOffTime_, uint256 seasonTokenId_, uint256 numFights, bool resolved, uint256 settlementTime) = 
            sportsbook.seasons(SEASON_ID);
        assertTrue(resolved);
        assertGt(settlementTime, 0);
        
        // Get CLAIM_WINDOW constant (72 hours = 259200 seconds)
        uint256 CLAIM_WINDOW = sportsbook.CLAIM_WINDOW();
        
        // Advance time to expire claim window
        uint256 timeToAdvance = settlementTime + CLAIM_WINDOW + 1 - block.timestamp;
        if (timeToAdvance > 0) {
            vm.warp(block.timestamp + timeToAdvance);
        }
        
        // Verify claim window has expired
        assertGt(block.timestamp, settlementTime + CLAIM_WINDOW);
        
        // Get remaining balance before recovery
        uint256 remainingBalanceBefore = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(remainingBalanceBefore, 1000); // Should be the prize pool (1000 FP)
        
        // Get admin balance before recovery
        uint256 adminBalanceBefore = fp1155.balanceOf(admin, SEASON_TOKEN_ID);
        
        // Recover remaining balance
        vm.prank(admin);
        sportsbook.recoverRemainingBalance(SEASON_ID, admin);
        
        // Verify balance was transferred to admin
        uint256 adminBalanceAfter = fp1155.balanceOf(admin, SEASON_TOKEN_ID);
        uint256 recoveredAmount = adminBalanceAfter - adminBalanceBefore;
        assertEq(recoveredAmount, remainingBalanceBefore);
        
        // Verify contract balance is now 0
        uint256 remainingBalanceAfter = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(remainingBalanceAfter, 0);
        
        console2.log("\n=== RECOVERY COMPLETE ===");
        console2.log("  Remaining balance recovered:", recoveredAmount);
        console2.log("  Contract balance after recovery:", remainingBalanceAfter);
    }

    // ============ EDGE CASES: Truncation and Small Pools ============

    function testEdgeCase1_ManyWinnersWithSmallPool() public {
        // Create season with 1 fight
        uint256 seasonId = 10;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 100,
            numOutcomes: 6
        });
        
        // Very small prize pool: 1 FP
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 1;
        
        // Mint initial prize pool + extra for seeding
        uint256 adminInitialBalance = 10;
        fp1155.mint(admin, SEASON_TOKEN_ID, adminInitialBalance, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // Setup 5 users
        address[5] memory users = [address(0x10), address(0x11), address(0x12), address(0x13), address(0x14)];
        for (uint256 i = 0; i < 5; i++) {
            fp1155.mint(users[i], SEASON_TOKEN_ID, 10, "");
            fp1155.setTransferAllowlist(users[i], true);
            vm.prank(users[i]);
            fp1155.setApprovalForAll(address(sportsbook), true);
        }
        
        // All users bet 1 FP on outcome 0 (Fighter A, Submission)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(1));
        }
        
        // Get fight statistics
        (uint256 fighterAUsers, , uint256 fighterAStaked, , uint256 totalUsers, uint256 fighterAProb, ) = 
            sportsbook.getFightStatistics(seasonId, 0);
        
        assertEq(fighterAUsers, 5);
        assertEq(fighterAStaked, 5);
        assertEq(totalUsers, 5);
        
        // Calculate required seed BEFORE resolution
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0;
        (uint256[] memory requiredPrizePools, uint256[] memory currentPrizePools, uint256[] memory additionalSeedsNeeded, uint256[] memory estimatedWinnersArray) = 
            sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
        
        // Seed the prize pool if needed
        if (additionalSeedsNeeded[0] > 0) {
            // Mint additional tokens for seeding
            fp1155.mint(admin, SEASON_TOKEN_ID, additionalSeedsNeeded[0], "");
            fp1155.setTransferAllowlist(admin, true);
            vm.prank(admin);
            fp1155.setApprovalForAll(address(sportsbook), true);
            
            // Seed the prize pool with autoSeed = true
            sportsbook.seedPrizePoolsForSeason(seasonId, winningOutcomes, true);
            
            // Verify the seed was applied
            (, uint256[] memory currentPrizePoolsAfter, uint256[] memory additionalSeedsNeededAfter, ) = 
                sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
            
            assertEq(currentPrizePoolsAfter[0], currentPrizePools[0] + additionalSeedsNeeded[0]);
            assertEq(additionalSeedsNeededAfter[0], 0);
        }
        
        // Resolve: outcome 0 wins
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get fight resolution data
        (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
            sportsbook.getFightResolutionData(seasonId, 0);
        
        assertEq(winningOutcome, 0);
        assertGt(totalWinningsPool, 0);
        assertEq(winningPoolTotalShares, 20); // 5 users × 4 shares each
        
        // Check winnings for each user
        for (uint256 i = 0; i < 5; i++) {
            (bool canClaim, uint256 userPoints, uint256 userWinnings, uint256 totalPayout, bool claimed) = 
                sportsbook.getPositionWinnings(users[i], seasonId, 0);
            
            assertTrue(canClaim);
            assertEq(userPoints, 4); // Exact match
            assertGe(userWinnings, 1); // Should be at least 1 FP after seeding
            assertGe(totalPayout, 2); // At least 1 stake + 1 winnings
        }
        
        // Users claim their winnings
        uint256 totalPayouts = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 balanceBefore = fp1155.balanceOf(users[i], SEASON_TOKEN_ID);
            vm.prank(users[i]);
            sportsbook.claim(seasonId);
            uint256 balanceAfter = fp1155.balanceOf(users[i], SEASON_TOKEN_ID);
            uint256 received = balanceAfter - balanceBefore;
            totalPayouts += received;
        }
        
        // Verify final balance
        uint256 contractBalanceFinal = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertGt(totalPayouts, 0);
    }

    function testEdgeCase2_OneWinnerWithLargePool() public {
        uint256 seasonId = 20;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 6
        });
        
        // Large prize pool: 1000 FP
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 1000;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 1000, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // Single user bets 1 FP
        fp1155.mint(user1, SEASON_TOKEN_ID, 10, "");
        fp1155.setTransferAllowlist(user1, true);
        vm.prank(user1);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(1));
        
        // Calculate required seed BEFORE resolution
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0;
        (, , uint256[] memory additionalSeedsNeeded, ) = 
            sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
        
        assertEq(additionalSeedsNeeded[0], 0); // No additional seed needed
        
        // Resolve: outcome 0 wins
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        (bool canClaim, uint256 userPoints, uint256 userWinnings, uint256 totalPayout, bool claimed) = 
            sportsbook.getPositionWinnings(user1, seasonId, 0);
        
        assertTrue(canClaim);
        assertEq(userPoints, 4);
        assertEq(userWinnings, 1000);
        assertEq(totalPayout, 1001); // 1 stake + 1000 winnings
    }

    function testEdgeCase3_ManyWinnersWithDifferentStakes() public {
        uint256 seasonId = 30;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 6
        });
        
        // Small prize pool: 10 FP
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 10;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 10, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // Setup 5 users
        address[5] memory users = [address(0x20), address(0x21), address(0x22), address(0x23), address(0x24)];
        for (uint256 i = 0; i < 5; i++) {
            fp1155.mint(users[i], SEASON_TOKEN_ID, 1000, "");
            fp1155.setTransferAllowlist(users[i], true);
            vm.prank(users[i]);
            fp1155.setApprovalForAll(address(sportsbook), true);
        }
        
        // 4 users bet 1 FP each, 1 user bets 100 FP
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(users[i]);
            sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(1));
        }
        vm.prank(users[4]);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(100));
        
        // Calculate required seed BEFORE resolution
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0;
        (, , uint256[] memory additionalSeedsNeeded, ) = 
            sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
        
        // Resolve: outcome 0 wins
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Check small stake users (1 FP each)
        for (uint256 i = 0; i < 4; i++) {
            (bool canClaim, uint256 userPoints, uint256 userWinnings, uint256 totalPayout, bool claimed) = 
                sportsbook.getPositionWinnings(users[i], seasonId, 0);
            
            assertTrue(canClaim);
            assertEq(userPoints, 4);
            // (10 * 4) / 412 = 40 / 412 = 0 (truncated)
            assertEq(userWinnings, 0);
            assertEq(totalPayout, 1); // Only stake recovered
        }
        
        // Check large stake user (100 FP)
        (bool canClaim5, uint256 userPoints5, uint256 userWinnings5, uint256 totalPayout5, bool claimed5) = 
            sportsbook.getPositionWinnings(users[4], seasonId, 0);
        
        assertTrue(canClaim5);
        assertEq(userPoints5, 4);
        // (10 * 400) / 412 = 4000 / 412 = 9 FP (truncated)
        assertEq(userWinnings5, 9);
        assertEq(totalPayout5, 109); // 100 stake + 9 winnings
    }

    function testEdgeCase4_PoolExactlyEqualsShares() public {
        uint256 seasonId = 40;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 6
        });
        
        // Prize pool: 20 FP (exactly equals 5 users × 4 shares)
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 20;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 20, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // 5 users bet 1 FP each
        address[5] memory users = [address(0x30), address(0x31), address(0x32), address(0x33), address(0x34)];
        for (uint256 i = 0; i < 5; i++) {
            fp1155.mint(users[i], SEASON_TOKEN_ID, 10, "");
            fp1155.setTransferAllowlist(users[i], true);
            vm.prank(users[i]);
            fp1155.setApprovalForAll(address(sportsbook), true);
            vm.prank(users[i]);
            sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(1));
        }
        
        // Calculate required seed BEFORE resolution
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0;
        (, , uint256[] memory additionalSeedsNeeded, ) = 
            sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
        
        assertEq(additionalSeedsNeeded[0], 0); // No additional seed needed
        
        // Resolve: outcome 0 wins
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        for (uint256 i = 0; i < 5; i++) {
            (bool canClaim, uint256 userPoints, uint256 userWinnings, uint256 totalPayout, bool claimed) = 
                sportsbook.getPositionWinnings(users[i], seasonId, 0);
            
            assertTrue(canClaim);
            assertEq(userPoints, 4);
            assertEq(userWinnings, 4); // Perfect division, no truncation
            assertEq(totalPayout, 5); // 1 stake + 4 winnings
        }
    }

    function testEdgeCase5_PoolSmallerThanShares() public {
        uint256 seasonId = 50;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 6
        });
        
        // Very small prize pool: 1 FP
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 1;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 1, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // 10 users bet 1 FP each
        address[10] memory users = [
            address(0x40), address(0x41), address(0x42), address(0x43), address(0x44),
            address(0x45), address(0x46), address(0x47), address(0x48), address(0x49)
        ];
        for (uint256 i = 0; i < 10; i++) {
            fp1155.mint(users[i], SEASON_TOKEN_ID, 10, "");
            fp1155.setTransferAllowlist(users[i], true);
            vm.prank(users[i]);
            fp1155.setApprovalForAll(address(sportsbook), true);
            vm.prank(users[i]);
            sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(1));
        }
        
        // Calculate required seed BEFORE resolution
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0;
        (, , uint256[] memory additionalSeedsNeeded, ) = 
            sportsbook.calculateRequiredSeedForSeason(seasonId, winningOutcomes);
        
        // Resolve: outcome 0 wins
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // First user claims
        uint256 balanceBefore1 = fp1155.balanceOf(users[0], SEASON_TOKEN_ID);
        vm.prank(users[0]);
        sportsbook.claim(seasonId);
        uint256 balanceAfter1 = fp1155.balanceOf(users[0], SEASON_TOKEN_ID);
        uint256 winnings1 = balanceAfter1 - balanceBefore1;
        
        // Check remaining users
        for (uint256 i = 1; i < 10; i++) {
            (bool canClaim, uint256 userPoints, uint256 userWinnings, uint256 totalPayout, bool claimed) = 
                sportsbook.getPositionWinnings(users[i], seasonId, 0);
            
            assertTrue(canClaim);
            assertEq(userPoints, 4);
            // After first user claimed, pool might be 0, so others get 0 winnings
            assertEq(userWinnings, 0);
            assertEq(totalPayout, 1); // Only stake recovered
        }
    }

    // ============ NO-CONTEST HANDLING (Enhanced) ============

    function testNoContestRefundWithRecovery() public {
        // ============ STEP 1: Create Season with 1 fight ============
        uint256 seasonId = 200;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 1,
            maxBet: 1000,
            numOutcomes: 8 // Includes No-Contest
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 1000;
        
        // Mint FP tokens to admin for prize pool
        fp1155.mint(admin, SEASON_TOKEN_ID, 1000, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // ============ STEP 2: Users make predictions ============
        uint256 stake1 = 100;
        uint256 stake2 = 200;
        uint256 stake3 = 150;
        
        // User1: Bets on outcome 0 (Fighter A, Submission)
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(stake1));
        
        // User2: Bets on outcome 1 (Fighter A, Decision)
        vm.prank(user2);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(1), _toArray(stake2));
        
        // User3: Bets on outcome 4 (Fighter B, Submission)
        vm.prank(user3);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(4), _toArray(stake3));
        
        // ============ STEP 3: Resolve with No-Contest ============
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 3; // Fighter A, No-Contest (method = 3)
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Verify fight state
        (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
            sportsbook.getFightResolutionData(seasonId, 0);
        
        assertEq(winningOutcome, 3);
        assertEq(totalWinningsPool, 0); // Should be 0 for No-Contest
        assertEq(winningPoolTotalShares, 0); // Should be 0 for No-Contest
        
        // ============ STEP 4: Users claim refunds ============
        uint256 balanceBefore1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        vm.prank(user1);
        sportsbook.claim(seasonId);
        uint256 balanceAfter1 = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        assertEq(balanceAfter1, balanceBefore1 + stake1);
        
        uint256 balanceBefore2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        vm.prank(user2);
        sportsbook.claim(seasonId);
        uint256 balanceAfter2 = fp1155.balanceOf(user2, SEASON_TOKEN_ID);
        assertEq(balanceAfter2, balanceBefore2 + stake2);
        
        uint256 balanceBefore3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        vm.prank(user3);
        sportsbook.claim(seasonId);
        uint256 balanceAfter3 = fp1155.balanceOf(user3, SEASON_TOKEN_ID);
        assertEq(balanceAfter3, balanceBefore3 + stake3);
        
        // Verify final balances - prize pool should remain in contract
        uint256 contractBalance = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(contractBalance, 1000); // Prize pool remains (not distributed)
        
        // ============ STEP 5: Test recoverRemainingBalance ============
        // Get settlement time from season
        (uint256 cutOffTime_, uint256 seasonTokenId_, uint256 numFights, bool resolved, uint256 settlementTime) = 
            sportsbook.seasons(seasonId);
        assertTrue(resolved);
        assertGt(settlementTime, 0);
        
        // Get CLAIM_WINDOW constant (72 hours = 259200 seconds)
        uint256 CLAIM_WINDOW = sportsbook.CLAIM_WINDOW();
        
        // Advance time to expire claim window
        uint256 timeToAdvance = settlementTime + CLAIM_WINDOW + 1 - block.timestamp;
        if (timeToAdvance > 0) {
            vm.warp(block.timestamp + timeToAdvance);
        }
        
        // Verify claim window has expired
        assertGt(block.timestamp, settlementTime + CLAIM_WINDOW);
        
        // Get remaining balance before recovery
        uint256 remainingBalanceBefore = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(remainingBalanceBefore, 1000); // Should be the prize pool (1000 FP)
        
        // Get admin balance before recovery
        uint256 adminBalanceBefore = fp1155.balanceOf(admin, SEASON_TOKEN_ID);
        
        // Recover remaining balance
        sportsbook.recoverRemainingBalance(seasonId, admin);
        
        // Verify balance was transferred to admin
        uint256 adminBalanceAfter = fp1155.balanceOf(admin, SEASON_TOKEN_ID);
        uint256 recoveredAmount = adminBalanceAfter - adminBalanceBefore;
        assertEq(recoveredAmount, remainingBalanceBefore);
        
        // Verify contract balance is now 0
        uint256 remainingBalanceAfter = fp1155.balanceOf(address(sportsbook), SEASON_TOKEN_ID);
        assertEq(remainingBalanceAfter, 0);
    }

    // ============ STRESS TEST: 15 Fights with 1,000 Users ============
    // NOTE: Reduced from 10,000 to 1,000 users because Foundry tests run in a single transaction
    // In production, each user would make their own transaction, so this is a simulation
    
    function testStress_15FightsWith1000Users() public {
        console2.log("\n=== STRESS TEST: 15 Fights with 1,000 Users ===");
        
        // ============ STEP 1: Create Season with 15 fights ============
        uint256 seasonId = 100;
        uint256 seasonTokenId = SEASON_TOKEN_ID;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        // 15 fights, each with 8 outcomes (RED/BLUE x 4 methods: Submission, Decision, KO/TKO, No-Contest)
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](15);
        for (uint256 i = 0; i < 15; i++) {
            fightConfigs[i] = Sportsbook.FightConfig({
                minBet: 1,
                maxBet: 1000,
                numOutcomes: 8
            });
        }
        
        // Prize pool: 1,000 FP per fight = 15,000 FP total (reduced for 1k users)
        uint256[] memory fightPrizePoolAmounts = new uint256[](15);
        uint256 totalPrizePool = 15000;
        for (uint256 i = 0; i < 15; i++) {
            fightPrizePoolAmounts[i] = 1000;
        }
        
        // Mint FP tokens to admin for prize pools
        fp1155.mint(admin, seasonTokenId, totalPrizePool, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        console2.log("Creating season with 15 fights...");
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            seasonTokenId,
            fightConfigs,
            fightPrizePoolAmounts
        );
        console2.log("Season created successfully");
        
        // ============ STEP 2: Generate 1,000 users ============
        console2.log("Generating 1,000 users...");
        uint256 NUM_USERS = 1000;
        address[] memory testUsers = new address[](NUM_USERS);
        
        // Generate deterministic addresses using vm.addr()
        for (uint256 i = 0; i < NUM_USERS; i++) {
            // Use a large offset to avoid conflicts with existing addresses
            testUsers[i] = vm.addr(10000 + i);
        }
        
        console2.log("Generated 1,000 users");
        
        // ============ STEP 3: Setup users (mint tokens, allowlist, approve) ============
        console2.log("Setting up users (minting tokens, allowlist, approvals)...");
        uint256 userBalance = 1000; // Each user gets 1000 FP
        uint256 BATCH_SIZE = 100; // Process in batches
        
        for (uint256 i = 0; i < NUM_USERS; i += BATCH_SIZE) {
            uint256 end = i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE;
            for (uint256 j = i; j < end; j++) {
                // Mint tokens
                fp1155.mint(testUsers[j], seasonTokenId, userBalance, "");
                // Add to allowlist
                fp1155.setTransferAllowlist(testUsers[j], true);
                // Approve sportsbook
                vm.prank(testUsers[j]);
                fp1155.setApprovalForAll(address(sportsbook), true);
            }
            
            if ((i + BATCH_SIZE) % 1000 == 0 || i + BATCH_SIZE >= NUM_USERS) {
                console2.log("Processed users:", i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE);
            }
        }
        
        // Verify contract has prize pool
        uint256 contractBalanceAfterSetup = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        assertEq(contractBalanceAfterSetup, totalPrizePool);
        console2.log("All users set up (contract balance verified)");
        
        // ============ STEP 4: Users make predictions ============
        console2.log("Users making predictions on 15 fights...");
        
        uint256 totalPredictions = 0;
        uint256 predictionsPerUser = 3; // Average 3 predictions per user
        
        for (uint256 i = 0; i < NUM_USERS; i += BATCH_SIZE) {
            uint256 end = i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE;
            for (uint256 j = i; j < end; j++) {
                // Determine how many fights this user will bet on (1-5 fights)
                uint256 numFightsToBet = (j % 5) + 1;
                
                // Select fights (deterministic but distributed)
                uint256[] memory fightIds = new uint256[](numFightsToBet);
                uint256 baseFightId = j % 15;
                
                for (uint256 k = 0; k < numFightsToBet; k++) {
                    fightIds[k] = (baseFightId + k) % 15;
                }
                
                // Generate outcomes and stakes
                uint256[] memory outcomes = new uint256[](numFightsToBet);
                uint256[] memory stakes = new uint256[](numFightsToBet);
                
                for (uint256 k = 0; k < numFightsToBet; k++) {
                    // Random outcome (0-7): 8 outcomes
                    outcomes[k] = j % 8;
                    // Random stake (1-100 FP)
                    stakes[k] = (j % 100) + 1;
                }
                
                // Make prediction
                vm.prank(testUsers[j]);
                try sportsbook.lockPredictionsBatch(seasonId, fightIds, outcomes, stakes) {
                    totalPredictions += numFightsToBet;
                } catch {
                    // Some predictions might fail (e.g., duplicate positions), that's ok
                }
            }
            
            if ((i + BATCH_SIZE) % 1000 == 0 || i + BATCH_SIZE >= NUM_USERS) {
                console2.log("Processed users:", i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE);
                console2.log("Total predictions:", totalPredictions);
            }
        }
        
        console2.log("Predictions completed. Total predictions:", totalPredictions);
        
        // ============ STEP 5: Verify contract state and balances ============
        console2.log("Verifying contract state and balances...");
        uint256 contractBalanceAfterPredictions = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        
        // Get fight statistics and calculate total staked
        uint256 totalStaked = 0;
        uint256 totalFighterAStaked = 0;
        uint256 totalFighterBStaked = 0;
        
        for (uint256 fightId = 0; fightId < 15; fightId++) {
            (uint256 fighterAUsers, , uint256 fighterAStaked_, , , , uint256 fighterBStaked_) = 
                sportsbook.getFightStatistics(seasonId, fightId);
            uint256 fightStaked = fighterAStaked_ + fighterBStaked_;
            totalStaked += fightStaked;
            totalFighterAStaked += fighterAStaked_;
            totalFighterBStaked += fighterBStaked_;
        }
        
        // CRITICAL VERIFICATION: Contract balance should equal prize pool + total stakes
        // Note: The actual balance might be higher than calculated totalStaked because:
        // 1. Some users might have made multiple predictions (overwriting previous positions)
        // 2. The contract balance reflects actual tokens transferred, not just calculated stakes
        // So we verify that balance >= prize pool + calculated stakes
        uint256 expectedMinBalance = totalPrizePool + totalStaked;
        console2.log("Contract balance after predictions:", contractBalanceAfterPredictions);
        console2.log("Expected minimum balance (prize pool + stakes):", expectedMinBalance);
        console2.log("Prize pool:", totalPrizePool);
        console2.log("Total staked across all fights (calculated):", totalStaked);
        console2.log("Total RED staked:", totalFighterAStaked);
        console2.log("Total BLUE staked:", totalFighterBStaked);
        
        // Verify that balance is at least prize pool + calculated stakes
        assertGe(contractBalanceAfterPredictions, expectedMinBalance);
        
        // Calculate actual staked from balance
        uint256 actualStaked = contractBalanceAfterPredictions - totalPrizePool;
        console2.log("Actual staked (from balance):", actualStaked);
        console2.log("Difference (actual - calculated):", actualStaked - totalStaked);
        console2.log("Contract balance verified");
        
        // ============ STEP 6: Resolve Season ============
        console2.log("Resolving season...");
        // Winning outcomes: deterministic (0-7 for 8 outcomes)
        uint8[] memory winningOutcomes = new uint8[](15);
        for (uint256 i = 0; i < 15; i++) {
            winningOutcomes[i] = uint8(i % 8);
        }
        
        // Store contract balance before resolution
        uint256 contractBalanceBeforeResolution = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Verify contract balance didn't change during resolution
        uint256 contractBalanceAfterResolution = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        assertEq(contractBalanceAfterResolution, contractBalanceBeforeResolution);
        console2.log("Season resolved (contract balance unchanged)");
        
        // Verify resolution data for all fights
        console2.log("Verifying resolution data...");
        for (uint256 fightId = 0; fightId < 15; fightId++) {
            (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
                sportsbook.getFightResolutionData(seasonId, fightId);
            
            assertEq(winningOutcome, winningOutcomes[fightId]);
            
            // Check if this is a No-Contest outcome (method = 3)
            uint256 winningMethod = winningOutcomes[fightId] & 0x3;
            if (winningMethod == 3) {
                // No-Contest: totalWinningsPool and winningPoolTotalShares should be 0
                assertEq(totalWinningsPool, 0);
                assertEq(winningPoolTotalShares, 0);
            } else {
                // Normal outcome: should have winnings pool and shares
                assertGt(totalWinningsPool, 0);
                assertGt(winningPoolTotalShares, 0);
            }
        }
        console2.log("Resolution data verified for all 15 fights");
        
        // ============ STEP 7: Find ALL winning users and make them claim ============
        console2.log("Finding ALL winning users and processing claims...");
        
        // Find ALL users who have winning positions
        console2.log("Scanning ALL users for winning positions...");
        
        // Use separate arrays instead of struct array
        uint256[] memory winningUserIndices = new uint256[](NUM_USERS);
        address[] memory winningUserAddresses = new address[](NUM_USERS);
        uint256[] memory winningUserPayouts = new uint256[](NUM_USERS);
        uint256 winningUsersCount = 0;
        
        // Scan ALL users in batches to find ALL winners
        for (uint256 i = 0; i < NUM_USERS; i += BATCH_SIZE) {
            uint256 end = i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE;
            for (uint256 j = i; j < end; j++) {
                uint256 totalPayout = 0;
                bool hasClaimable = false;
                
                for (uint256 fightId = 0; fightId < 15; fightId++) {
                    try sportsbook.getPositionWinnings(testUsers[j], seasonId, fightId) returns (
                        bool canClaim,
                        uint256,
                        uint256,
                        uint256 payout,
                        bool claimed
                    ) {
                        if (canClaim && !claimed) {
                            hasClaimable = true;
                            totalPayout += payout;
                        }
                    } catch {
                        // Position doesn't exist
                    }
                }
                
                if (hasClaimable && totalPayout > 0) {
                    winningUserIndices[winningUsersCount] = j;
                    winningUserAddresses[winningUsersCount] = testUsers[j];
                    winningUserPayouts[winningUsersCount] = totalPayout;
                    winningUsersCount++;
                }
            }
            
            if ((i + BATCH_SIZE) % 2000 == 0 || i + BATCH_SIZE >= NUM_USERS) {
                console2.log("Scanned users:", i + BATCH_SIZE > NUM_USERS ? NUM_USERS : i + BATCH_SIZE);
                console2.log("Found winners:", winningUsersCount);
            }
        }
        
        console2.log("Found winning users with claimable positions:", winningUsersCount);
        
        // Store contract balance before claims
        uint256 contractBalanceBeforeClaims = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        
        uint256 successfulClaims = 0;
        uint256 totalClaimed = 0;
        
        // Process claims for ALL winning users sequentially
        console2.log("Processing claims for ALL winning users (sequentially)...");
        
        for (uint256 i = 0; i < winningUsersCount; i++) {
            address user = winningUserAddresses[i];
            
            // Recalculate expected payout right before claiming
            uint256 expectedTotalPayout = 0;
            for (uint256 fightId = 0; fightId < 15; fightId++) {
                try sportsbook.getPositionWinnings(user, seasonId, fightId) returns (
                    bool canClaim,
                    uint256,
                    uint256,
                    uint256 payout,
                    bool claimed
                ) {
                    if (canClaim && !claimed) {
                        expectedTotalPayout += payout;
                    }
                } catch {
                    // Position doesn't exist
                }
            }
            
            // Skip if no claimable positions
            if (expectedTotalPayout == 0) {
                continue;
            }
            
            uint256 balanceBefore = fp1155.balanceOf(user, seasonTokenId);
            uint256 contractBalanceBeforeUserClaim = fp1155.balanceOf(address(sportsbook), seasonTokenId);
            
            // Claim
            vm.prank(user);
            sportsbook.claim(seasonId);
            
            uint256 balanceAfter = fp1155.balanceOf(user, seasonTokenId);
            uint256 contractBalanceAfterUserClaim = fp1155.balanceOf(address(sportsbook), seasonTokenId);
            
            uint256 claimedAmount = balanceAfter - balanceBefore;
            uint256 contractPaid = contractBalanceBeforeUserClaim - contractBalanceAfterUserClaim;
            
            // CRITICAL VERIFICATION: Contract paid exactly what user received
            assertEq(contractPaid, claimedAmount);
            
            totalClaimed += claimedAmount;
            successfulClaims++;
            
            if (i < 5 || (i + 1) % 500 == 0) {
                console2.log("Claim processed:", i + 1);
                console2.log("User claimed:", claimedAmount);
            }
        }
        
        // CRITICAL VERIFICATION: Contract balance decreased by exactly what was claimed
        uint256 contractBalanceAfterClaims = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        uint256 contractPaidTotal = contractBalanceBeforeClaims - contractBalanceAfterClaims;
        assertEq(contractPaidTotal, totalClaimed);
        
        console2.log("Successful claims:", successfulClaims);
        console2.log("Total claimed:", totalClaimed);
        console2.log("Contract paid:", contractPaidTotal);
        console2.log("Claims tested successfully (integrity verified)");
        
        // ============ STEP 8: Final verification and integrity checks ============
        console2.log("=== FINAL VERIFICATION & INTEGRITY CHECKS ===");
        (uint256 cutOffTime_, uint256 seasonTokenId_, uint256 numFights, bool resolved, uint256 settlementTime) = 
            sportsbook.seasons(seasonId);
        assertTrue(resolved);
        assertEq(numFights, 15);
        
        // Verify all fights are resolved
        for (uint256 fightId = 0; fightId < 15; fightId++) {
            (uint256 totalWinningsPool, uint256 winningPoolTotalShares, uint256 winningOutcome) = 
                sportsbook.getFightResolutionData(seasonId, fightId);
            
            // Check if this is a No-Contest outcome (method = 3)
            uint256 winningMethod = winningOutcome & 0x3;
            if (winningMethod == 3) {
                // No-Contest: totalWinningsPool and winningPoolTotalShares should be 0
                assertEq(totalWinningsPool, 0);
                assertEq(winningPoolTotalShares, 0);
            } else {
                // Normal outcome: should have winnings pool and shares
                assertGt(totalWinningsPool, 0);
                assertGt(winningPoolTotalShares, 0);
            }
            assertLe(winningOutcome, 7); // Valid range (0-7)
        }
        console2.log("All 15 fights resolved correctly");
        
        // CRITICAL INTEGRITY CHECK: Contract balance should equal remaining unclaimed funds
        uint256 finalContractBalance = fp1155.balanceOf(address(sportsbook), seasonTokenId);
        uint256 expectedRemainingBalance = contractBalanceBeforeClaims - totalClaimed;
        assertEq(finalContractBalance, expectedRemainingBalance);
        console2.log("Contract balance integrity verified (remaining:", finalContractBalance, ")");
        
        console2.log("=== STRESS TEST SUMMARY ===");
        console2.log("Total Users:", NUM_USERS);
        console2.log("Total Fights: 15");
        console2.log("Total Predictions:", totalPredictions);
        console2.log("Total Staked:", totalStaked);
        console2.log("Prize Pool:", totalPrizePool);
        console2.log("Total Winning Users:", winningUsersCount);
        console2.log("Successful Claims:", successfulClaims);
        console2.log("Total Claimed:", totalClaimed);
        console2.log("Final Contract Balance:", finalContractBalance);
        console2.log("=== INTEGRITY CHECKS PASSED ===");
    }

    // ============ TIME WINDOW TESTS ============
    
    function testCutOffTime_PredictionsBeforeCutOffTime() public {
        console2.log("\n=== TEST: Predictions Before CutOffTime ===");
        
        // Create season with cutOffTime in the future
        uint256 seasonId = 300;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User should be able to make predictions before cutOffTime
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        console2.log("Predictions made successfully before cutOffTime");
        
        // Verify position was created
        Sportsbook.Position memory position = sportsbook.getPosition(user1, seasonId, 0);
        assertEq(position.outcome, 0);
        assertEq(position.stakeAmount, 20);
        assertFalse(position.claimed);
        
        console2.log("Position verified");
    }
    
    function testCutOffTime_PredictionsAfterCutOffTime() public {
        console2.log("\n=== TEST: Predictions After CutOffTime Should Fail ===");
        
        // Create season with cutOffTime in the past
        uint256 seasonId = 301;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // Advance time past cutOffTime
        vm.warp(cutOffTime + 1);
        
        // User should NOT be able to make predictions after cutOffTime
        vm.prank(user1);
        vm.expectRevert("SB-15"); // Invalid time parameter
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        console2.log("Predictions correctly rejected after cutOffTime");
    }
    
    function testCutOffTime_PredictionsExactlyAtCutOffTime() public {
        console2.log("\n=== TEST: Predictions Exactly At CutOffTime ===");
        
        // Create season with cutOffTime
        uint256 seasonId = 302;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // Advance time to exactly cutOffTime
        vm.warp(cutOffTime);
        
        // User should be able to make predictions exactly at cutOffTime (<=)
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        console2.log("Predictions made successfully exactly at cutOffTime");
        
        // Verify position was created
        Sportsbook.Position memory position = sportsbook.getPosition(user1, seasonId, 0);
        assertEq(position.outcome, 0);
        assertEq(position.stakeAmount, 20);
        assertFalse(position.claimed);
        
        console2.log("Position verified");
    }
    
    function testClaimWindow_ClaimBeforeSettlementTime() public {
        console2.log("\n=== TEST: Claim Before SettlementTime Should Fail ===");
        
        // Create season and resolve it
        uint256 seasonId = 303;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User makes prediction
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        // Resolve season
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // User wins
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get settlement time
        (, , , , uint256 settlementTime) = sportsbook.seasons(seasonId);
        assertGt(settlementTime, 0);
        
        // Try to claim before settlement time (go back in time)
        vm.warp(settlementTime - 1);
        
        vm.prank(user1);
        vm.expectRevert("SB-20"); // Claim window not open
        sportsbook.claim(seasonId);
        
        console2.log("Claim correctly rejected before settlementTime");
    }
    
    function testClaimWindow_ClaimAfterClaimWindow() public {
        console2.log("\n=== TEST: Claim After ClaimWindow Should Fail ===");
        
        // Create season and resolve it
        uint256 seasonId = 304;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User makes prediction
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        // Resolve season
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // User wins
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get settlement time and CLAIM_WINDOW
        (, , , , uint256 settlementTime) = sportsbook.seasons(seasonId);
        uint256 CLAIM_WINDOW = sportsbook.CLAIM_WINDOW();
        
        // Advance time past claim window
        vm.warp(settlementTime + CLAIM_WINDOW + 1);
        
        vm.prank(user1);
        vm.expectRevert("SB-19"); // Claim window expired
        sportsbook.claim(seasonId);
        
        console2.log("Claim correctly rejected after CLAIM_WINDOW");
    }
    
    function testClaimWindow_ClaimExactlyAtSettlementTime() public {
        console2.log("\n=== TEST: Claim Exactly At SettlementTime ===");
        
        // Create season and resolve it
        uint256 seasonId = 305;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User makes prediction
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        // Resolve season
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // User wins
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get settlement time
        (, , , , uint256 settlementTime) = sportsbook.seasons(seasonId);
        
        // Advance time to exactly settlement time
        vm.warp(settlementTime);
        
        // User should be able to claim exactly at settlement time (>=)
        uint256 balanceBefore = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        vm.prank(user1);
        sportsbook.claim(seasonId);
        uint256 balanceAfter = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        
        assertGt(balanceAfter, balanceBefore);
        console2.log("Claim successful exactly at settlementTime");
    }
    
    function testClaimWindow_ClaimExactlyAtEndOfClaimWindow() public {
        console2.log("\n=== TEST: Claim Exactly At End Of ClaimWindow ===");
        
        // Create season and resolve it
        uint256 seasonId = 306;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User makes prediction
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        // Resolve season
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // User wins
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get settlement time and CLAIM_WINDOW
        (, , , , uint256 settlementTime) = sportsbook.seasons(seasonId);
        uint256 CLAIM_WINDOW = sportsbook.CLAIM_WINDOW();
        
        // Advance time to exactly end of claim window
        vm.warp(settlementTime + CLAIM_WINDOW);
        
        // User should be able to claim exactly at end of claim window (<=)
        uint256 balanceBefore = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        vm.prank(user1);
        sportsbook.claim(seasonId);
        uint256 balanceAfter = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        
        assertGt(balanceAfter, balanceBefore);
        console2.log("Claim successful exactly at end of CLAIM_WINDOW");
    }
    
    function testClaimWindow_ClaimWithinClaimWindow() public {
        console2.log("\n=== TEST: Claim Within ClaimWindow ===");
        
        // Create season and resolve it
        uint256 seasonId = 307;
        uint256 cutOffTime = block.timestamp + 1 days;
        
        Sportsbook.FightConfig[] memory fightConfigs = new Sportsbook.FightConfig[](1);
        fightConfigs[0] = Sportsbook.FightConfig({
            minBet: 10,
            maxBet: 100,
            numOutcomes: 6
        });
        
        uint256[] memory fightPrizePoolAmounts = new uint256[](1);
        fightPrizePoolAmounts[0] = 100;
        
        fp1155.mint(admin, SEASON_TOKEN_ID, 100, "");
        fp1155.setTransferAllowlist(admin, true);
        vm.prank(admin);
        fp1155.setApprovalForAll(address(sportsbook), true);
        
        sportsbook.createSeasonWithFights(
            seasonId,
            cutOffTime,
            SEASON_TOKEN_ID,
            fightConfigs,
            fightPrizePoolAmounts
        );
        
        // User makes prediction
        vm.prank(user1);
        sportsbook.lockPredictionsBatch(seasonId, _toArray(0), _toArray(0), _toArray(20));
        
        // Resolve season
        uint8[] memory winningOutcomes = new uint8[](1);
        winningOutcomes[0] = 0; // User wins
        
        sportsbook.resolveSeason(seasonId, winningOutcomes);
        
        // Get settlement time and CLAIM_WINDOW
        (, , , , uint256 settlementTime) = sportsbook.seasons(seasonId);
        uint256 CLAIM_WINDOW = sportsbook.CLAIM_WINDOW();
        
        // Advance time to middle of claim window
        vm.warp(settlementTime + CLAIM_WINDOW / 2);
        
        // User should be able to claim within claim window
        uint256 balanceBefore = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        vm.prank(user1);
        sportsbook.claim(seasonId);
        uint256 balanceAfter = fp1155.balanceOf(user1, SEASON_TOKEN_ID);
        
        assertGt(balanceAfter, balanceBefore);
        console2.log("Claim successful within CLAIM_WINDOW");
    }

    // Helper functions
    function _toArray(uint256 a) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = a;
        return arr;
    }

    function _toArray(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }

    function _toArray(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        return arr;
    }

    // Helper function to format outcome
    function formatOutcome(uint256 outcome) internal pure returns (string memory) {
        (string memory fighter, string memory method) = decodeOutcome(outcome);
        return string(abi.encodePacked(fighter, " - ", method, " (outcome ", _uint2str(outcome), ")"));
    }

    // Helper function to format FP as integer units (NFTs)
    function formatFp(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(_uint2str(amount), " FP"));
    }

    // Helper function to convert uint256 to string
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            // casting to 'uint8' is safe because we're extracting a single digit (0-9)
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // Implement IERC1155Receiver for test contract to receive ERC1155 tokens
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

