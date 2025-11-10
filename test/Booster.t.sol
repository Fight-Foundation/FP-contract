// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Booster} from "../src/Booster.sol";
import {FP1155} from "../src/FP1155.sol";

contract BoosterTest is Test {
    Booster public booster;
    FP1155 public fp;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    uint256 constant SEASON_1 = 1;
    string constant EVENT_1 = "UFC_300";
    uint256 constant FIGHT_1 = 1;
    uint256 constant FIGHT_2 = 2;
    uint256 constant FIGHT_3 = 3;
    uint256 constant INVALID_FIGHT_ID = 99; // Used for testing invalid fightId scenarios

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy FP1155
        fp = new FP1155("https://api.fightfoundation.io/fp/", admin);
        
        // Deploy Booster
        booster = new Booster(address(fp), admin);
        
        // Grant roles
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(booster));
        fp.grantRole(fp.MINTER_ROLE(), admin);
        
        booster.grantRole(booster.OPERATOR_ROLE(), operator);
        
        // Mint FP to users
        fp.mint(user1, SEASON_1, 10000 ether, "");
        fp.mint(user2, SEASON_1, 10000 ether, "");
        fp.mint(user3, SEASON_1, 10000 ether, "");
    fp.mint(operator, SEASON_1, 50000 ether, "");

        // Allowlist participants for transfers
        fp.setTransferAllowlist(user1, true);
        fp.setTransferAllowlist(user2, true);
        fp.setTransferAllowlist(user3, true);
    fp.setTransferAllowlist(operator, true);
        
        vm.stopPrank();
    }

    // ============ Event Creation Tests ============

    function test_createEvent() public {
        uint256 numFights = 3;

    vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit Booster.EventCreated(EVENT_1, numFights, SEASON_1);
        booster.createEvent(EVENT_1, numFights, SEASON_1);

        // Verify event exists
        (uint256 seasonId, uint256 storedNumFights, bool exists) = booster.getEvent(EVENT_1);
        assertTrue(exists);
        assertEq(seasonId, SEASON_1);
        assertEq(storedNumFights, 3);

        // Verify all fights initialized as OPEN
        (Booster.FightStatus status,,,,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(status), uint256(Booster.FightStatus.OPEN));

        // Set a claim deadline
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, deadline);
        assertEq(booster.getEventClaimDeadline(EVENT_1), deadline);
    }

    function testRevert_createEvent_notOperator() public {
    vm.prank(user1);
        vm.expectRevert();
        booster.createEvent(EVENT_1, 1, SEASON_1);
    }

    function testRevert_createEvent_duplicate() public {
    vm.startPrank(operator);
        booster.createEvent(EVENT_1, 1, SEASON_1);
        
        vm.expectRevert("event exists");
        booster.createEvent(EVENT_1, 1, SEASON_1);
        vm.stopPrank();
    }

    function testRevert_createEvent_emptyFights() public {
    vm.prank(operator);
        vm.expectRevert("no fights");
        booster.createEvent(EVENT_1, 0, SEASON_1);
    }

    // ============ Boost Placement Tests ============

    function test_placeBoosts() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](2);
        boosts[0] = Booster.BoostInput({
            fightId: FIGHT_1,
            amount: 100 ether,
            predictedWinner: Booster.Corner.RED,
            predictedMethod: Booster.WinMethod.KNOCKOUT
        });
        boosts[1] = Booster.BoostInput({
            fightId: FIGHT_2,
            amount: 200 ether,
            predictedWinner: Booster.Corner.BLUE,
            predictedMethod: Booster.WinMethod.SUBMISSION
        });

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Booster.BoostPlaced(EVENT_1, FIGHT_1, user1, 0, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts);

        // Verify boosts created
        Booster.Boost[] memory userBoosts1 = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts1.length, 1);
        assertEq(userBoosts1[0].amount, 100 ether);
        assertEq(uint256(userBoosts1[0].predictedWinner), uint256(Booster.Corner.RED));

        Booster.Boost[] memory userBoosts2 = booster.getUserBoosts(EVENT_1, FIGHT_2, user1);
        assertEq(userBoosts2.length, 1);
        assertEq(userBoosts2[0].amount, 200 ether);

        // Verify FP transferred
        assertEq(fp.balanceOf(user1, SEASON_1), 10000 ether - 300 ether);
        assertEq(fp.balanceOf(address(booster), SEASON_1), 300 ether);

        // Verify originalPool updated
        (, , , , uint256 originalPool, , , , , , , ) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(originalPool, 100 ether);
    }

    function testRevert_placeBoosts_eventNotExists() public {
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        vm.prank(user1);
        vm.expectRevert("event not exists");
        booster.placeBoosts("FAKE_EVENT", boosts);
    }

    function testRevert_placeBoosts_fightNotOpen() public {
        _createDefaultEvent();
        
        // Close fight
    vm.prank(operator);
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        vm.prank(user1);
        vm.expectRevert("fight not open");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function testRevert_placeBoosts_zeroAmount() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 0, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        vm.prank(user1);
        vm.expectRevert("amount=0");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function testRevert_placeBoosts_invalidFightId() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(INVALID_FIGHT_ID, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        vm.prank(user1);
        vm.expectRevert("fightId not in event");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function testRevert_placeBoosts_multipleInputsWithInvalidFightId() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](2);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts[1] = Booster.BoostInput(INVALID_FIGHT_ID, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION); // Invalid fightId

        vm.prank(user1);
        vm.expectRevert("fightId not in event");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function test_placeBoosts_validFightIds() public {
        _createDefaultEvent();

        // Place boosts with all valid fightIds from the event
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](3);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts[1] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        boosts[2] = Booster.BoostInput(FIGHT_3, 300 ether, Booster.Corner.RED, Booster.WinMethod.DECISION);

        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Verify all boosts were created
        Booster.Boost[] memory userBoosts1 = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        Booster.Boost[] memory userBoosts2 = booster.getUserBoosts(EVENT_1, FIGHT_2, user1);
        Booster.Boost[] memory userBoosts3 = booster.getUserBoosts(EVENT_1, FIGHT_3, user1);

        assertEq(userBoosts1.length, 1);
        assertEq(userBoosts2.length, 1);
        assertEq(userBoosts3.length, 1);
        assertEq(userBoosts1[0].amount, 100 ether);
        assertEq(userBoosts2[0].amount, 200 ether);
        assertEq(userBoosts3[0].amount, 300 ether);
    }

    // ============ Add to Boost Tests ============

    function test_addToBoost() public {
        _createDefaultEvent();
        
        // Place initial boost
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Add to boost
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Booster.BoostIncreased(EVENT_1, FIGHT_1, user1, 0, 50 ether, 150 ether);
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 50 ether);

        // Verify boost amount increased
        Booster.Boost[] memory userBoosts = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts[0].amount, 150 ether);

        // Verify FP transferred
        assertEq(fp.balanceOf(user1, SEASON_1), 10000 ether - 150 ether);

        // Verify originalPool updated
        (, , , , uint256 originalPool, , , , , , , ) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(originalPool, 150 ether);
    }

    function testRevert_addToBoost_notOwner() public {
        _createDefaultEvent();
        
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        vm.prank(user2);
        vm.expectRevert("not boost owner");
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 50 ether);
    }

    function testRevert_addToBoost_fightNotOpen() public {
        _createDefaultEvent();
        
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Close fight
    vm.prank(operator);
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);

        vm.prank(user1);
        vm.expectRevert("fight not open");
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 50 ether);
    }

    function testRevert_addToBoost_invalidIndex() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert("invalid boost index");
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 50 ether);
    }

    function testRevert_addToBoost_invalidFightId() public {
        _createDefaultEvent();
        
        // Place initial boost on valid fight
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Try to add to boost with invalid fightId (not in event)
        vm.prank(user1);
        vm.expectRevert("fightId not in event");
        booster.addToBoost(EVENT_1, INVALID_FIGHT_ID, 0, 50 ether);
    }

    // ============ Bonus Deposit Tests ============

    function test_depositBonus() public {
        _createDefaultEvent();

    vm.prank(operator);
    vm.expectEmit(true, true, true, true);
    emit Booster.BonusDeposited(EVENT_1, FIGHT_1, operator, 1000 ether);
    booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether);

        // Verify bonus pool updated
    (, , , uint256 bonusPool, , , , , , , , ) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 1000 ether);

        // Verify FP transferred
    assertEq(fp.balanceOf(operator, SEASON_1), 50000 ether - 1000 ether);
        assertEq(fp.balanceOf(address(booster), SEASON_1), 1000 ether);
    }

    function test_depositBonus_multiple() public {
        _createDefaultEvent();

    vm.startPrank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 500 ether);
        booster.depositBonus(EVENT_1, FIGHT_1, 300 ether);
        vm.stopPrank();

        (, , , uint256 bonusPool, , , , , , , , ) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 800 ether);
    }

    function testRevert_depositBonus_notManager() public {
        _createDefaultEvent();

    vm.prank(user1);
    vm.expectRevert();
    booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether);
    }

    function testRevert_depositBonus_resolved() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

    vm.prank(operator);
        vm.expectRevert("fight resolved");
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether);
    }

    // ============ Fight Status Tests ============

    function test_updateFightStatus() public {
        _createDefaultEvent();

    vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightStatusUpdated(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);

        (Booster.FightStatus status,,,,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(status), uint256(Booster.FightStatus.CLOSED));
    }

    function testRevert_updateFightStatus_backwards() public {
        _createDefaultEvent();

    vm.startPrank(operator);
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);
        
        vm.expectRevert("invalid status transition");
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.OPEN);
        vm.stopPrank();
    }

    function testRevert_updateFightStatus_afterResolved() public {
        _createDefaultEvent();

    vm.startPrank(operator);
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.RESOLVED);
        
        vm.expectRevert("fight already resolved");
        booster.updateFightStatus(EVENT_1, FIGHT_1, Booster.FightStatus.CLOSED);
        vm.stopPrank();
    }

    // ============ Submit Fight Result Tests ============

    function test_submitFightResult() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightResultSubmitted(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            40
        );
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10, // pointsForWinner
            20, // pointsForWinnerMethod
            40  // totalWinningPoints (calculated offchain)
        );

        // Verify fight result stored
        (
            Booster.FightStatus status,
            Booster.Corner winner,
            Booster.WinMethod method,
            ,,
            uint256 totalWinningPoints,
            uint256 pointsForWinner,
            uint256 pointsForWinnerMethod,
            ,,,
            bool cancelled
        ) = booster.getFight(EVENT_1, FIGHT_1);

        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED));
        assertEq(uint256(winner), uint256(Booster.Corner.RED));
        assertEq(uint256(method), uint256(Booster.WinMethod.KNOCKOUT));
        assertEq(totalWinningPoints, 40);
        assertEq(pointsForWinner, 10);
        assertEq(pointsForWinnerMethod, 20);
        assertFalse(cancelled); // calculationSubmitted is redundant: if status == RESOLVED && !cancelled, calculation was submitted
    }

    function testRevert_submitFightResult_notOperator() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert();
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 30);
    }

    function testRevert_submitFightResult_alreadyResolved() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        vm.prank(operator);
        vm.expectRevert("already resolved");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 30);
    }

    function test_submitFightResult_noWinners() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        // Submit result with no winners (totalWinningPoints = 0)
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightResultSubmitted(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            0  // No winners
        );
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            0  // totalWinningPoints = 0 means no winners
        );

        // Verify fight is resolved
        (Booster.FightStatus status, , , , , uint256 totalWinningPoints, , , , , , ) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED));
        assertEq(totalWinningPoints, 0);
    }

    function testRevert_claimReward_noWinners() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        // Submit result with no winners
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            0
        );

        // Try to claim - should revert because no winners
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        vm.expectRevert("no winners");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function test_quoteClaimable_noWinners() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            0
        );
        // Quote claimable should return zeros when no winners
        (uint256 totalClaimable, uint256 originalShare, uint256 bonusShare) = 
            booster.quoteClaimable(EVENT_1, FIGHT_1, user1, false);
        
        assertEq(totalClaimable, 0);
        assertEq(originalShare, 0);
        assertEq(bonusShare, 0);
    }

    // ============ Claim Reward Tests ============

    function test_claimReward_winnerOnly() public {
        _createDefaultEvent();
        
        // User1: RED + KNOCKOUT (correct winner, correct method) = 20 points
        // User2: RED + SUBMISSION (correct winner, wrong method) = 10 points
        // User3: BLUE + KNOCKOUT (wrong winner) = 0 points
        
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts1);

        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_1, 200 ether, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts2);

        vm.prank(user3);
        Booster.BoostInput[] memory boosts3 = new Booster.BoostInput[](1);
        boosts3[0] = Booster.BoostInput(FIGHT_1, 300 ether, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts3);

        // Total originalPool: 600 ether
        // Winning points: user1=20, user2=10, total=30

        // Submit result
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 30);

    // Fetch correct index for user1 boost
    uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
    assertEq(indices1.length, 1);

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Booster.RewardClaimed(EVENT_1, FIGHT_1, user1, 0, 400 ether, 20);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);

        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 400 ether);

    // Fetch correct index for user2 boost (should differ from user1's index)
    uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);
    assertEq(indices2.length, 1);

        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, indices2);

        assertEq(fp.balanceOf(user2, SEASON_1), 10000 ether - 200 ether + 200 ether); // Gets back what they put in
    }

    function test_claimReward_withBonus() public {
        _createDefaultEvent();
        
        // Add bonus pool
    vm.prank(operator);
    booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether);

        // User1: RED + KNOCKOUT = 20 points
        vm.prank(user1);
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts);

        // Total pool: 100 (original) + 1000 (bonus) = 1100 ether
        // User1 is only winner with 20 points

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 20);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        // User1 gets entire pool: 1100 ether
        assertEq(fp.balanceOf(user1, SEASON_1), 10000 ether - 100 ether + 1100 ether);

        // Set short deadline and advance beyond it, check purge sweeps remaining (none expected)
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 1);
        vm.warp(block.timestamp + 2);
        vm.prank(operator);
        booster.purgeEvent(EVENT_1, operator); // should sweep zero
    }

    function test_claimReward_multipleBoosts() public {
        _createDefaultEvent();

        // User1 places 2 boosts on same fight
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](2);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts[1] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Resolve: RED + KNOCKOUT
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 30);

        // Claim both boosts at once
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0; // 20 points
        indices[1] = 1; // 10 points
        
        // Total: (20+10)/30 * 150 = 150 ether (all of it)
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        assertEq(fp.balanceOf(user1, SEASON_1), 10000 ether); // Gets everything back

        // Set deadline and attempt purge (should sweep zero)
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 1);
        vm.warp(block.timestamp + 2);
        vm.prank(operator);
        booster.purgeEvent(EVENT_1, operator);
    }

    function testRevert_placeBoost_afterBoostCutoff() public {
        _createDefaultEvent();
        vm.prank(operator);
        booster.setFightBoostCutoff(EVENT_1, FIGHT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function testRevert_addToBoost_afterBoostCutoff() public {
        _createDefaultEvent();
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);
        vm.prank(operator);
        booster.setFightBoostCutoff(EVENT_1, FIGHT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 10 ether);
    }

    function testRevert_claimReward_afterDeadline() public {
        _createDefaultEvent();
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 20);
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        vm.prank(user1);
        vm.expectRevert("claim deadline passed");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function test_purgeEvent_sweepsUnclaimed() public {
        _createDefaultEvent();
        // Two users place boosts but only one claims before deadline
        Booster.BoostInput[] memory boostsA = new Booster.BoostInput[](1);
        boostsA[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boostsA);

        Booster.BoostInput[] memory boostsB = new Booster.BoostInput[](1);
        boostsB[0] = Booster.BoostInput(FIGHT_1, 200 ether, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        vm.prank(user2);
        booster.placeBoosts(EVENT_1, boostsB);

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 30);

        // user1 claims (20/30)*300 = 200
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);

        // Set deadline and warp past
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);

        uint256 operatorBefore = fp.balanceOf(operator, SEASON_1);
        vm.prank(operator);
        booster.purgeEvent(EVENT_1, operator);
        uint256 operatorAfter = fp.balanceOf(operator, SEASON_1);

        // Remaining unclaimed points (user2): (10/30)*300 = 100 swept
        assertEq(operatorAfter - operatorBefore, 100 ether);
    }

    function testRevert_claimReward_notResolved() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        vm.expectRevert("not resolved");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimReward_notOwner() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user2);
        vm.expectRevert("not boost owner");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimReward_alreadyClaimed() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        vm.prank(user1);
        vm.expectRevert("already claimed");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimReward_loser() public {
        _createDefaultEvent();

        // User1: RED (loser)
        vm.prank(user1);
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts);

        // Resolve: BLUE wins
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT, 10, 20, 20);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        vm.expectRevert("boost did not win");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    // ============ View Function Tests ============

    function test_calculateUserPoints() public {
        // Exact match
        uint256 points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20
        );
        assertEq(points, 20);

        // Winner only
        points = booster.calculateUserPoints(
            Booster.Corner.RED,
            Booster.WinMethod.SUBMISSION,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20
        );
        assertEq(points, 10);

        // Wrong winner
        points = booster.calculateUserPoints(
            Booster.Corner.BLUE,
            Booster.WinMethod.KNOCKOUT,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20
        );
        assertEq(points, 0);
    }

    function test_getUserBoosts() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](2);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts[1] = Booster.BoostInput(FIGHT_1, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        Booster.Boost[] memory userBoosts = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts.length, 2);
        assertEq(userBoosts[0].amount, 100 ether);
        assertEq(userBoosts[1].amount, 200 ether);
    }

    // ============ Helper Functions ============

    function _createDefaultEvent() internal {
    vm.prank(operator);
        booster.createEvent(EVENT_1, 3, SEASON_1);
    }

    function _placeMultipleBoosts() internal {
        vm.prank(user1);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts1);

        vm.prank(user2);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_1, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        booster.placeBoosts(EVENT_1, boosts2);
    }

    function _placeBoostsAndResolve() internal {
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 20);
    }

    // ============ Cancellation Tests ============

    function test_cancelFight_refundsAll() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        uint256 user1Before = fp.balanceOf(user1, SEASON_1);
        uint256 user2Before = fp.balanceOf(user2, SEASON_1);

        // Cancel fight
        vm.prank(operator);
        vm.expectEmit(true, true, false, false);
        emit Booster.FightCancelled(EVENT_1, FIGHT_1);
        booster.cancelFight(EVENT_1, FIGHT_1);

        // Verify fight marked as cancelled
        (,,,,,,,,,,, bool cancelled) = booster.getFight(EVENT_1, FIGHT_1);
        assertTrue(cancelled);

        // User1 claims refund
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);
        assertEq(fp.balanceOf(user1, SEASON_1), user1Before + 100 ether);

        // User2 claims refund
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);
        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, indices2);
        assertEq(fp.balanceOf(user2, SEASON_1), user2Before + 200 ether);
    }

    function testRevert_cancelFight_alreadyResolved() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        vm.prank(operator);
        vm.expectRevert("fight already resolved");
        booster.cancelFight(EVENT_1, FIGHT_1);
    }

    // ============ Min Boost Amount Tests ============

    function test_setMinBoostAmount() public {
        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit Booster.MinBoostAmountUpdated(0, 10 ether);
        booster.setMinBoostAmount(10 ether);

        assertEq(booster.minBoostAmount(), 10 ether);
    }

    function testRevert_placeBoost_belowMinimum() public {
        _createDefaultEvent();
        
        vm.prank(operator);
        booster.setMinBoostAmount(50 ether);

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 10 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        vm.prank(user1);
        vm.expectRevert("below min boost");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function testRevert_addToBoost_belowMinimum() public {
        _createDefaultEvent();

        // Place initial boost
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Set minimum
        vm.prank(operator);
        booster.setMinBoostAmount(50 ether);

        // Try to add below minimum
        vm.prank(user1);
        vm.expectRevert("below min boost");
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 10 ether);
    }

    // ============ Points Validation Tests ============

    function testRevert_submitResult_zeroPointsForWinner() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("points for winner must be > 0");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 0, 20, 30);
    }

    function testRevert_submitResult_methodPointsLessThanWinner() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("method points must be >= winner points");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 20, 10, 30);
    }

    function testRevert_submitResult_noneWinnerWithoutNoContest() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("NONE winner requires NO_CONTEST method");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.NONE, Booster.WinMethod.KNOCKOUT, 10, 20, 30);
    }

    function test_submitResult_noneWinnerWithNoContest() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.NONE, Booster.WinMethod.NO_CONTEST, 10, 20, 30);

        (,Booster.Corner winner, Booster.WinMethod method,,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(winner), uint256(Booster.Corner.NONE));
        assertEq(uint256(method), uint256(Booster.WinMethod.NO_CONTEST));
    }

    // ============ View Function Tests ============

    function test_totalPool() public {
        _createDefaultEvent();

        // Place boosts
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Deposit bonus
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 500 ether);

        // Check totalPool
        assertEq(booster.totalPool(EVENT_1, FIGHT_1), 600 ether);
    }
}
