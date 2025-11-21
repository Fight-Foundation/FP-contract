// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { Booster } from "../src/Booster.sol";
import { FP1155 } from "../src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

        // Mint FP to users
        fp.mint(user1, SEASON_1, 10_000 ether, "");
        fp.mint(user2, SEASON_1, 10_000 ether, "");
        fp.mint(user3, SEASON_1, 10_000 ether, "");
        fp.mint(operator, SEASON_1, 50_000 ether, "");

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
        booster.createEvent(EVENT_1, numFights, SEASON_1, 0);

        // Verify event exists
        (uint256 seasonId, uint256 storedNumFights, bool exists, bool claimReady) = booster.getEvent(EVENT_1);
        assertTrue(exists);
        assertFalse(claimReady); // Should be false initially
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
        booster.createEvent(EVENT_1, 1, SEASON_1, 0);
    }

    function testRevert_createEvent_duplicate() public {
        vm.startPrank(operator);
        booster.createEvent(EVENT_1, 1, SEASON_1, 0);

        vm.expectRevert("event exists");
        booster.createEvent(EVENT_1, 1, SEASON_1, 0);
        vm.stopPrank();
    }

    function testRevert_createEvent_emptyFights() public {
        vm.prank(operator);
        vm.expectRevert("no fights");
        booster.createEvent(EVENT_1, 0, SEASON_1, 0);
    }

    function test_createEvent_withDefaultBoostCutoff() public {
        uint256 numFights = 3;
        uint256 cutoff = block.timestamp + 1 days;

        vm.prank(operator);
        // No events emitted for initial cutoff setup (it's part of event creation, not a change)
        booster.createEvent(EVENT_1, numFights, SEASON_1, cutoff);

        // Verify all fights have the cutoff set
        (,,,,,,,,,, uint256 boostCutoff1,) = booster.getFight(EVENT_1, FIGHT_1);
        (,,,,,,,,,, uint256 boostCutoff2,) = booster.getFight(EVENT_1, FIGHT_2);
        (,,,,,,,,,, uint256 boostCutoff3,) = booster.getFight(EVENT_1, FIGHT_3);

        assertEq(boostCutoff1, cutoff);
        assertEq(boostCutoff2, cutoff);
        assertEq(boostCutoff3, cutoff);
    }

    function test_createEvent_withZeroCutoff() public {
        uint256 numFights = 3;

        vm.prank(operator);
        booster.createEvent(EVENT_1, numFights, SEASON_1, 0);

        // Verify all fights have no cutoff (0)
        (,,,,,,,,,, uint256 boostCutoff1,) = booster.getFight(EVENT_1, FIGHT_1);
        (,,,,,,,,,, uint256 boostCutoff2,) = booster.getFight(EVENT_1, FIGHT_2);
        (,,,,,,,,,, uint256 boostCutoff3,) = booster.getFight(EVENT_1, FIGHT_3);

        assertEq(boostCutoff1, 0);
        assertEq(boostCutoff2, 0);
        assertEq(boostCutoff3, 0);
    }

    function test_createEvent_withDefaultBoostCutoff_preventsBoostsAfterCutoff() public {
        uint256 cutoff = block.timestamp + 10;
        vm.prank(operator);
        booster.createEvent(EVENT_1, 3, SEASON_1, cutoff);

        // Advance past cutoff
        vm.warp(block.timestamp + 11);

        // Try to place boost - should fail
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.placeBoosts(EVENT_1, boosts);
    }

    function test_createEvent_withDefaultBoostCutoff_allowsBoostsBeforeCutoff() public {
        uint256 cutoff = block.timestamp + 100;
        vm.prank(operator);
        booster.createEvent(EVENT_1, 3, SEASON_1, cutoff);

        // Place boost before cutoff - should succeed
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Verify boost was placed
        Booster.Boost[] memory userBoosts = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts[0].amount, 50 ether);
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
        assertEq(fp.balanceOf(user1, SEASON_1), 10_000 ether - 300 ether);
        assertEq(fp.balanceOf(address(booster), SEASON_1), 300 ether);

        // Verify originalPool updated
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
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
        assertEq(fp.balanceOf(user1, SEASON_1), 10_000 ether - 150 ether);

        // Verify originalPool updated
        (,,,, uint256 originalPool,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
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
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether, false);

        // Verify bonus pool updated
        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 1000 ether);

        // Verify FP transferred
        assertEq(fp.balanceOf(operator, SEASON_1), 50_000 ether - 1000 ether);
        assertEq(fp.balanceOf(address(booster), SEASON_1), 1000 ether);
    }

    function test_depositBonus_multiple() public {
        _createDefaultEvent();

        vm.startPrank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 500 ether, false);
        booster.depositBonus(EVENT_1, FIGHT_1, 300 ether, false);
        vm.stopPrank();

        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 800 ether);
    }

    function testRevert_depositBonus_notManager() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert();
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether, false);
    }

    function testRevert_depositBonus_resolved() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        vm.prank(operator);
        vm.expectRevert("fight resolved");
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether, false);
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

        // _placeMultipleBoosts: user1=100 ether (RED+KNOCKOUT, winner), user2=200 ether (BLUE+SUBMISSION, loser)
        // sumWinnersStakes = 100 ether, winningPoolTotalShares = 20 * 100 = 2000 ether
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightResultSubmitted(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            100 ether, // sumWinnersStakes
            2000 ether // winningPoolTotalShares
        );
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10, // pointsForWinner
            20, // pointsForWinnerMethod
            100 ether, // sumWinnersStakes
            2000 ether // winningPoolTotalShares
        );

        // Verify fight result stored
        (
            Booster.FightStatus status,
            Booster.Corner winner,
            Booster.WinMethod method,,,
            uint256 sumWinnersStakes,
            uint256 winningPoolTotalShares,
            uint256 pointsForWinner,
            uint256 pointsForWinnerMethod,,,
            bool cancelled
        ) = booster.getFight(EVENT_1, FIGHT_1);

        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED));
        assertEq(uint256(winner), uint256(Booster.Corner.RED));
        assertEq(uint256(method), uint256(Booster.WinMethod.KNOCKOUT));
        assertEq(sumWinnersStakes, 100 ether); // Sum of stakes
        assertEq(winningPoolTotalShares, 2000 ether); // Total shares
        assertEq(pointsForWinner, 10);
        assertEq(pointsForWinnerMethod, 20);
        assertFalse(cancelled); // calculationSubmitted is redundant: if status == RESOLVED && !cancelled, calculation was submitted
    }

    function testRevert_submitFightResult_notOperator() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert();
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 3, 30);
    }

    function testRevert_submitFightResult_alreadyClaimReady() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        // Mark event as claim ready - now results cannot be updated
        _setEventClaimReady(EVENT_1);

        vm.prank(operator);
        vm.expectRevert("event claim ready");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 3);
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
            0, // sumWinnersStakes - No winners
            0 // winningPoolTotalShares - No winners
        );
        booster.submitFightResult(
            EVENT_1,
            FIGHT_1,
            Booster.Corner.RED,
            Booster.WinMethod.KNOCKOUT,
            10,
            20,
            0, // sumWinnersStakes = 0 means no winners
            0 // winningPoolTotalShares = 0 means no winners
        );

        // Verify fight is resolved
        (Booster.FightStatus status,,,,, uint256 sumWinnersStakes, uint256 winningPoolTotalShares,,,,,) =
            booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED));
        assertEq(sumWinnersStakes, 0);
        assertEq(winningPoolTotalShares, 0);
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
            0, // sumWinnersStakes
            0 // winningPoolTotalShares
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Try to claim - should revert because no winners, so nothing to claim
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        vm.expectRevert("nothing to claim");
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
            0, // sumWinnersStakes
            0 // winningPoolTotalShares
        );
        // Quote claimable should return zeros when no winners
        uint256 totalClaimable = booster.quoteClaimable(EVENT_1, FIGHT_1, user1, false);

        assertEq(totalClaimable, 0);
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
        // Winning points: user1=20, user2=10
        // sumWinnersStakes = 100 + 200 = 300 ether (both users won)
        // winningPoolTotalShares = (20 * 100) + (10 * 200) = 2000 + 2000 = 4000 ether

        // Submit result
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 300 ether, 4000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Fetch correct index for user1 boost
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        assertEq(indices1.length, 1);

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        // Calculate expected payout:
        // prizePool = originalPool - sumWinnersStakes + bonusPool = 600 - 300 + 0 = 300 ether
        // user1: points=20, stake=100, userShares=2000
        // userWinnings = (300 * 2000) / 4000 = 150 ether
        // payout = 100 + 150 = 250 ether
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Booster.RewardClaimed(EVENT_1, FIGHT_1, user1, 0, 250 ether, 20);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);

        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 250 ether);

        // Fetch correct index for user2 boost (should differ from user1's index)
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);
        assertEq(indices2.length, 1);

        // user2: points=10, stake=200, userShares=2000
        // userWinnings = (300 * 2000) / 4000 = 150 ether
        // payout = 200 + 150 = 350 ether
        uint256 balanceBefore2 = fp.balanceOf(user2, SEASON_1);
        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, indices2);

        assertEq(fp.balanceOf(user2, SEASON_1), balanceBefore2 + 350 ether);
    }

    function test_claimReward_withBonus() public {
        _createDefaultEvent();

        // Add bonus pool
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether, false);

        // User1: RED + KNOCKOUT = 20 points
        vm.prank(user1);
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        booster.placeBoosts(EVENT_1, boosts);

        // Total pool: 100 (original) + 1000 (bonus) = 1100 ether
        // User1 is only winner with 20 points
        // sumWinnersStakes = 100 ether
        // winningPoolTotalShares = 20 * 100 = 2000 ether

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        // User1 gets entire pool: 1100 ether
        assertEq(fp.balanceOf(user1, SEASON_1), 10_000 ether - 100 ether + 1100 ether);

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
        // Both boosts win: boost0 = 20 points, boost1 = 10 points
        // sumWinnersStakes = 100 + 50 = 150 ether
        // winningPoolTotalShares = (20 * 100) + (10 * 50) = 2000 + 500 = 2500 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 150 ether, 2500 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim both boosts at once
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0; // 20 points
        indices[1] = 1; // 10 points

        // User gets back their stakes (150 ether) plus winnings from prizePool
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        assertEq(fp.balanceOf(user1, SEASON_1), 10_000 ether); // Gets everything back

        // Set deadline and attempt purge (should sweep zero)
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 1);
        vm.warp(block.timestamp + 2);
        vm.prank(operator);
        booster.purgeEvent(EVENT_1, operator);
    }

    function test_placeBoost_atBoostCutoff() public {
        _createDefaultEvent();
        uint256 cutoff = block.timestamp + 10;
        vm.prank(operator);
        booster.setFightBoostCutoff(EVENT_1, FIGHT_1, cutoff);

        // Warp to exact cutoff time (inclusive behavior)
        vm.warp(cutoff);

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Verify boost was placed
        Booster.Boost[] memory userBoosts = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts.length, 1);
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

    function test_addToBoost_atBoostCutoff() public {
        _createDefaultEvent();
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        uint256 cutoff = block.timestamp + 10;
        vm.prank(operator);
        booster.setFightBoostCutoff(EVENT_1, FIGHT_1, cutoff);

        // Warp to exact cutoff time (inclusive behavior)
        vm.warp(cutoff);

        vm.prank(user1);
        booster.addToBoost(EVENT_1, FIGHT_1, 0, 10 ether);

        // Verify boost was increased
        Booster.Boost[] memory userBoosts = booster.getUserBoosts(EVENT_1, FIGHT_1, user1);
        assertEq(userBoosts[0].amount, 60 ether);
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

    // ============ Set Event Boost Cutoff Tests ============

    function test_setEventBoostCutoff_allFights() public {
        _createDefaultEvent();

        uint256 cutoff = block.timestamp + 100;

        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightBoostCutoffUpdated(EVENT_1, FIGHT_1, cutoff);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightBoostCutoffUpdated(EVENT_1, FIGHT_2, cutoff);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightBoostCutoffUpdated(EVENT_1, FIGHT_3, cutoff);
        booster.setEventBoostCutoff(EVENT_1, cutoff);

        // Verify all fights have the cutoff set
        (,,,,,,,,,, uint256 boostCutoff1,) = booster.getFight(EVENT_1, FIGHT_1);
        (,,,,,,,,,, uint256 boostCutoff2,) = booster.getFight(EVENT_1, FIGHT_2);
        (,,,,,,,,,, uint256 boostCutoff3,) = booster.getFight(EVENT_1, FIGHT_3);

        assertEq(boostCutoff1, cutoff);
        assertEq(boostCutoff2, cutoff);
        assertEq(boostCutoff3, cutoff);
    }

    function test_setEventBoostCutoff_skipsResolvedFights() public {
        _createDefaultEvent();

        // Resolve fight 2
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_2, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 0, 0);

        uint256 cutoff = block.timestamp + 100;

        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit Booster.FightBoostCutoffUpdated(EVENT_1, FIGHT_1, cutoff);
        // FIGHT_2 should not emit event (already resolved)
        vm.expectEmit(true, true, false, true);
        emit Booster.FightBoostCutoffUpdated(EVENT_1, FIGHT_3, cutoff);
        booster.setEventBoostCutoff(EVENT_1, cutoff);

        // Verify fight 1 and 3 have cutoff set
        (,,,,,,,,,, uint256 boostCutoff1,) = booster.getFight(EVENT_1, FIGHT_1);
        (,,,,,,,,,, uint256 boostCutoff2,) = booster.getFight(EVENT_1, FIGHT_2);
        (,,,,,,,,,, uint256 boostCutoff3,) = booster.getFight(EVENT_1, FIGHT_3);

        assertEq(boostCutoff1, cutoff);
        assertEq(boostCutoff2, 0); // Resolved fight should not be updated
        assertEq(boostCutoff3, cutoff);
    }

    function test_setEventBoostCutoff_zeroCutoff() public {
        _createDefaultEvent();

        // First set a cutoff
        uint256 initialCutoff = block.timestamp + 100;
        vm.prank(operator);
        booster.setEventBoostCutoff(EVENT_1, initialCutoff);

        // Then set to 0 (disable cutoff)
        vm.prank(operator);
        booster.setEventBoostCutoff(EVENT_1, 0);

        // Verify all fights have cutoff set to 0
        (,,,,,,,,,, uint256 boostCutoff1,) = booster.getFight(EVENT_1, FIGHT_1);
        (,,,,,,,,,, uint256 boostCutoff2,) = booster.getFight(EVENT_1, FIGHT_2);
        (,,,,,,,,,, uint256 boostCutoff3,) = booster.getFight(EVENT_1, FIGHT_3);

        assertEq(boostCutoff1, 0);
        assertEq(boostCutoff2, 0);
        assertEq(boostCutoff3, 0);
    }

    function test_setEventBoostCutoff_preventsBoostsAfterCutoff() public {
        _createDefaultEvent();

        uint256 cutoff = block.timestamp + 10;
        vm.prank(operator);
        booster.setEventBoostCutoff(EVENT_1, cutoff);

        // Advance past cutoff
        vm.warp(block.timestamp + 11);

        // Try to place boost on all fights - should fail
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.placeBoosts(EVENT_1, boosts1);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.placeBoosts(EVENT_1, boosts2);

        Booster.BoostInput[] memory boosts3 = new Booster.BoostInput[](1);
        boosts3[0] = Booster.BoostInput(FIGHT_3, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        vm.expectRevert("boost cutoff passed");
        booster.placeBoosts(EVENT_1, boosts3);
    }

    function testRevert_setEventBoostCutoff_notOperator() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert();
        booster.setEventBoostCutoff(EVENT_1, block.timestamp + 100);
    }

    function testRevert_setEventBoostCutoff_eventNotExists() public {
        vm.prank(operator);
        vm.expectRevert("event not exists");
        booster.setEventBoostCutoff("FAKE_EVENT", block.timestamp + 100);
    }

    function test_setEventBoostCutoff_largeEvent() public {
        // Create event with many fights
        vm.prank(operator);
        booster.createEvent("UFC_301", 10, SEASON_1, 0);

        uint256 cutoff = block.timestamp + 100;

        vm.prank(operator);
        booster.setEventBoostCutoff("UFC_301", cutoff);

        // Verify all 10 fights have cutoff set
        for (uint256 i = 1; i <= 10; i++) {
            (,,,,,,,,,, uint256 boostCutoff,) = booster.getFight("UFC_301", i);
            assertEq(boostCutoff, cutoff);
        }
    }

    function testRevert_claimReward_afterDeadline() public {
        _createDefaultEvent();
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 50 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 2);
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);
        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);
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

        // Both users win: user1 (20pts, 100eth), user2 (10pts, 200eth)
        // sumWinnersStakes = 100 + 200 = 300 ether
        // winningPoolTotalShares = (20*100) + (10*200) = 2000 + 2000 = 4000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 300 ether, 4000 ether
        );

        // user1 claims: prizePool = 300 - 300 + 0 = 0, so gets back stake (100) + 0 = 100 ether
        // Actually, with the new formula: userShares = 20*100 = 2000, winnings = (0*2000)/4000 = 0
        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // So user1 gets: 100 + 0 = 100 ether (just stake back)
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

        // Remaining unclaimed: user2's stake (200) + user2's winnings from prizePool
        // prizePool = 300 - 300 + 0 = 0, so user2 would get: 200 + 0 = 200 ether
        // But since user2 didn't claim, the entire unclaimed amount is swept
        // Actually, the unclaimed pool is: originalPool - sumWinnersStakes = 300 - 300 = 0
        // So nothing should be swept... wait, let me recalculate
        // originalPool = 300, sumWinnersStakes = 300, so unclaimedPool = 0
        // But user2's stake (200) is part of sumWinnersStakes, so user2 should be able to claim 200
        // Since user2 didn't claim, 200 ether should be swept
        assertEq(operatorAfter - operatorBefore, 200 ether);
    }

    function testRevert_claimReward_notResolved() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        // Mark event as claim ready (even though fight is not resolved)
        _setEventClaimReady(EVENT_1);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        vm.expectRevert("not resolved");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimReward_notOwner() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user2);
        vm.expectRevert("not boost owner");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimReward_alreadyClaimed() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

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
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 2);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.prank(user1);
        vm.expectRevert("boost did not win");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    // ============ View Function Tests ============

    function test_calculateUserPoints() public view {
        // Exact match
        uint256 points = booster.calculateUserPoints(
            Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20
        );
        assertEq(points, 20);

        // Winner only
        points = booster.calculateUserPoints(
            Booster.Corner.RED, Booster.WinMethod.SUBMISSION, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20
        );
        assertEq(points, 10);

        // Wrong winner
        points = booster.calculateUserPoints(
            Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20
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

    function test_getEventFights() public {
        // Create event with 5 fights
        vm.prank(operator);
        booster.createEvent(EVENT_1, 5, SEASON_1, 0);

        // Get all fights - should all be OPEN initially
        (uint256[] memory fightIds, Booster.FightStatus[] memory statuses) = booster.getEventFights(EVENT_1);

        assertEq(fightIds.length, 5, "Should have 5 fights");
        assertEq(statuses.length, 5, "Should have 5 statuses");

        // Verify fight IDs are 1, 2, 3, 4, 5
        for (uint256 i = 0; i < 5; i++) {
            assertEq(fightIds[i], i + 1, "Fight ID should match index + 1");
            assertEq(uint256(statuses[i]), uint256(Booster.FightStatus.OPEN), "All fights should be OPEN initially");
        }

        // Update some fight statuses
        vm.prank(operator);
        booster.updateFightStatus(EVENT_1, 1, Booster.FightStatus.CLOSED);

        vm.prank(operator);
        booster.updateFightStatus(EVENT_1, 2, Booster.FightStatus.CLOSED);

        vm.prank(operator);
        booster.updateFightStatus(EVENT_1, 3, Booster.FightStatus.RESOLVED);

        // Get fights again and verify statuses
        (fightIds, statuses) = booster.getEventFights(EVENT_1);

        assertEq(uint256(statuses[0]), uint256(Booster.FightStatus.CLOSED), "Fight 1 should be CLOSED");
        assertEq(uint256(statuses[1]), uint256(Booster.FightStatus.CLOSED), "Fight 2 should be CLOSED");
        assertEq(uint256(statuses[2]), uint256(Booster.FightStatus.RESOLVED), "Fight 3 should be RESOLVED");
        assertEq(uint256(statuses[3]), uint256(Booster.FightStatus.OPEN), "Fight 4 should be OPEN");
        assertEq(uint256(statuses[4]), uint256(Booster.FightStatus.OPEN), "Fight 5 should be OPEN");
    }

    function testRevert_getEventFights_eventNotExists() public {
        vm.expectRevert("event not exists");
        booster.getEventFights(EVENT_1);
    }

    function test_getEventFights_singleFight() public {
        // Create event with 1 fight
        vm.prank(operator);
        booster.createEvent(EVENT_1, 1, SEASON_1, 0);

        (uint256[] memory fightIds, Booster.FightStatus[] memory statuses) = booster.getEventFights(EVENT_1);

        assertEq(fightIds.length, 1, "Should have 1 fight");
        assertEq(statuses.length, 1, "Should have 1 status");
        assertEq(fightIds[0], 1, "Fight ID should be 1");
        assertEq(uint256(statuses[0]), uint256(Booster.FightStatus.OPEN), "Fight should be OPEN initially");
    }

    // ============ Helper Functions ============

    function _createDefaultEvent() internal {
        vm.prank(operator);
        booster.createEvent(EVENT_1, 3, SEASON_1, 0);
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

        // Calculate correct values:
        // user1: 100 ether on RED + KNOCKOUT (winner) = 20 points
        // user2: 200 ether on BLUE + SUBMISSION (loser) = 0 points
        // sumWinnersStakes = 100 ether (only user1 won)
        // winningPoolTotalShares = 20 * 100 = 2000 (points * stake)
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );
    }

    function _setEventClaimReady(string memory eventId) internal {
        vm.prank(operator);
        booster.setEventClaimReady(eventId, true);
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

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

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

    // ============ Maximum Limits Tests ============

    function test_setMaxFightsPerEvent() public {
        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit Booster.MaxFightsPerEventUpdated(20, 50);
        booster.setMaxFightsPerEvent(50);

        assertEq(booster.maxFightsPerEvent(), 50);
    }

    function test_createEvent_withinMaxFights() public {
        // Default max is 20, create event with 20 fights
        vm.prank(operator);
        booster.createEvent(EVENT_1, 20, SEASON_1, 0);

        (,, bool exists,) = booster.getEvent(EVENT_1);
        assertTrue(exists);
    }

    function testRevert_createEvent_exceedsMaxFights() public {
        // Default max is 20, try to create event with 21 fights
        vm.prank(operator);
        vm.expectRevert("numFights exceeds maximum");
        booster.createEvent(EVENT_1, 21, SEASON_1, 0);
    }

    function test_createEvent_unlimitedWhenMaxIsZero() public {
        // Set max to 0 (unlimited)
        vm.prank(operator);
        booster.setMaxFightsPerEvent(0);

        // Should be able to create event with any number of fights
        vm.prank(operator);
        booster.createEvent(EVENT_1, 100, SEASON_1, 0);

        (,, bool exists,) = booster.getEvent(EVENT_1);
        assertTrue(exists);
    }

    function test_setMaxBonusDeposit() public {
        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit Booster.MaxBonusDepositUpdated(0, 1000 ether);
        booster.setMaxBonusDeposit(1000 ether);

        assertEq(booster.maxBonusDeposit(), 1000 ether);
    }

    function test_depositBonus_withinMax() public {
        _createDefaultEvent();

        // Set max bonus deposit
        vm.prank(operator);
        booster.setMaxBonusDeposit(1000 ether);

        // Should be able to deposit up to the limit
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 1000 ether, false);

        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 1000 ether);
    }

    function testRevert_depositBonus_exceedsMax() public {
        _createDefaultEvent();

        // Set max bonus deposit
        vm.prank(operator);
        booster.setMaxBonusDeposit(1000 ether);

        // Try to deposit more than the limit
        vm.prank(operator);
        vm.expectRevert("bonus deposit exceeds maximum");
        booster.depositBonus(EVENT_1, FIGHT_1, 1001 ether, false);
    }

    function test_depositBonus_unlimitedWhenMaxIsZero() public {
        _createDefaultEvent();

        // Max is 0 by default (unlimited), should be able to deposit any amount
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 10_000 ether, false);

        (,,, uint256 bonusPool,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(bonusPool, 10_000 ether);
    }

    function testRevert_setMaxFightsPerEvent_notOperator() public {
        vm.prank(user1);
        vm.expectRevert();
        booster.setMaxFightsPerEvent(50);
    }

    function testRevert_setMaxBonusDeposit_notOperator() public {
        vm.prank(user1);
        vm.expectRevert();
        booster.setMaxBonusDeposit(1000 ether);
    }

    // ============ Points Validation Tests ============

    function testRevert_submitResult_zeroPointsForWinner() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("points for winner must be > 0");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 0, 20, 10, 3);
    }

    function testRevert_submitResult_methodPointsLessThanWinner() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("method points must be >= winner points");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 20, 10, 10, 3);
    }

    function testRevert_submitResult_noneWinnerWithoutNoContest() public {
        _createDefaultEvent();

        vm.prank(operator);
        vm.expectRevert("NONE winner requires NO_CONTEST method");
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.NONE, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 3);
    }

    function test_submitResult_noneWinnerWithNoContest() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.NONE, Booster.WinMethod.NO_CONTEST, 10, 20, 10, 3);

        (, Booster.Corner winner, Booster.WinMethod method,,,,,,,,, bool cancelled) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(winner), uint256(Booster.Corner.NONE));
        assertEq(uint256(method), uint256(Booster.WinMethod.NO_CONTEST));
        // Verify that cancelled flag is automatically set for no-contest outcomes
        assertTrue(cancelled, "fight should be marked as cancelled for no-contest");
    }

    function test_submitResult_noContest_enablesRefunds() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        uint256 user1Before = fp.balanceOf(user1, SEASON_1);
        uint256 user2Before = fp.balanceOf(user2, SEASON_1);

        // Submit no-contest result via submitFightResult
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.NONE, Booster.WinMethod.NO_CONTEST, 10, 20, 0, 0);

        // Verify fight is marked as cancelled
        (,,,,,,,,,,, bool cancelled) = booster.getFight(EVENT_1, FIGHT_1);
        assertTrue(cancelled, "fight should be marked as cancelled");

        // Mark event as claim ready (required even for refunds)
        _setEventClaimReady(EVENT_1);

        // Users should be able to claim refunds
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);

        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices1);
        assertEq(fp.balanceOf(user1, SEASON_1), user1Before + 100 ether);

        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, indices2);
        assertEq(fp.balanceOf(user2, SEASON_1), user2Before + 200 ether);
    }

    // ============ Claim Rewards (Multiple Fights) Tests ============

    function test_claimRewards_multipleFights() public {
        _createDefaultEvent();

        // User1 places boosts on multiple fights
        // FIGHT_1: 3 boosts with different corners and methods
        // Using values that result in exact divisions
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](3);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts1[1] = Booster.BoostInput(FIGHT_1, 70 ether, Booster.Corner.BLUE, Booster.WinMethod.DECISION);
        boosts1[2] = Booster.BoostInput(FIGHT_1, 80 ether, Booster.Corner.RED, Booster.WinMethod.SUBMISSION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        // FIGHT_2: 3 boosts with different corners and methods
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](3);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        boosts2[1] = Booster.BoostInput(FIGHT_2, 120 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosts2[2] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.DECISION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts2);

        // Resolve both fights
        // FIGHT_1: Winning boosts are 0 (RED+KNOCKOUT, 20pts, 100eth) and 2 (RED+SUBMISSION, 10pts, 80eth)
        // sumWinnersStakes = 100 + 80 = 180 ether
        // winningPoolTotalShares = (20*100) + (10*80) = 2000 + 800 = 2800 ether
        // originalPool = 100 + 70 + 80 = 250 ether
        // prizePool = 250 - 180 = 70 ether
        // Calculations: (70*2000)/2800 = 50, (70*800)/2800 = 20 (both exact)
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 180 ether, 2800 ether
        );
        // FIGHT_2: Winning boosts are 0 (BLUE+SUBMISSION, 20pts, 200eth) and 2 (BLUE+DECISION, 10pts, 200eth)
        // sumWinnersStakes = 200 + 200 = 400 ether
        // winningPoolTotalShares = (20*200) + (10*200) = 4000 + 2000 = 6000 ether
        // originalPool = 200 + 120 + 200 = 520 ether
        // prizePool = 520 - 400 = 120 ether
        // Calculations: (120*4000)/6000 = 80, (120*2000)/6000 = 40 (both exact)
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_2, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION, 10, 20, 400 ether, 6000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim rewards from both fights in one transaction
        // Only claim winning boosts (indices 0 and 2 for FIGHT_1, indices 0 and 2 for FIGHT_2)
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](2);
        uint256[] memory indices1 = new uint256[](2);
        indices1[0] = 0; // RED + KNOCKOUT → 20 points
        indices1[1] = 2; // RED + SUBMISSION → 10 points

        uint256[] memory indices2 = new uint256[](2);
        indices2[0] = 0; // BLUE + SUBMISSION → 20 points
        indices2[1] = 2; // BLUE + DECISION → 10 points

        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices1 });
        claims[1] = Booster.ClaimInput({ fightId: FIGHT_2, boostIndices: indices2 });

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        vm.prank(user1);
        booster.claimRewards(EVENT_1, claims);

        // User1 should get proportional rewards based on points:
        // FIGHT_1: originalPool=250, sumWinnersStakes=180, prizePool=70
        //          Boost 0 (20pts, 100eth): winnings=(70*2000)/2800=50, payout=150
        //          Boost 2 (10pts, 80eth): winnings=(70*800)/2800=20, payout=100
        //          Total: 250 ether (exact)
        // FIGHT_2: originalPool=520, sumWinnersStakes=400, prizePool=120
        //          Boost 0 (20pts, 200eth): winnings=(120*4000)/6000=80, payout=280
        //          Boost 2 (10pts, 200eth): winnings=(120*2000)/6000=40, payout=240
        //          Total: 520 ether (exact)
        // Total: 250 + 520 = 770 ether
        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 770 ether);
    }

    function test_claimRewards_withBonusPools() public {
        _createDefaultEvent();

        // Place boosts
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts2);

        // Add bonus pools
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, 500 ether, false);

        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_2, 1000 ether, false);

        // Resolve fights
        // FIGHT_1: user1 wins with 100 ether stake, 20 points
        // sumWinnersStakes = 100 ether, winningPoolTotalShares = 20 * 100 = 2000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // FIGHT_2: user1 wins with 200 ether stake, 20 points
        // sumWinnersStakes = 200 ether, winningPoolTotalShares = 20 * 200 = 4000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_2, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION, 10, 20, 200 ether, 4000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim rewards
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](2);
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_2, user1);

        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices1 });
        claims[1] = Booster.ClaimInput({ fightId: FIGHT_2, boostIndices: indices2 });

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        vm.prank(user1);
        booster.claimRewards(EVENT_1, claims);

        // Fight 1: prizePool = 100 - 100 + 500 = 500 ether
        //          user1 gets: stake (100) + winnings (500 * 2000 / 2000 = 500) = 600 ether
        // Fight 2: prizePool = 200 - 200 + 1000 = 1000 ether
        //          user1 gets: stake (200) + winnings (1000 * 4000 / 4000 = 1000) = 1200 ether
        // Total: 600 + 1200 = 1800 ether
        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 1800 ether);
    }

    function test_claimRewards_mixedCancelledAndWinning() public {
        _createDefaultEvent();

        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_2, 1000 ether, false);

        // User1 places boosts on multiple fights
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts2);

        // Cancel fight 1, resolve fight 2
        vm.prank(operator);
        booster.cancelFight(EVENT_1, FIGHT_1);

        // FIGHT_2: user1 wins with 200 ether stake, 20 points
        // sumWinnersStakes = 200 ether, winningPoolTotalShares = 20 * 200 = 4000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_2, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION, 10, 20, 200 ether, 4000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim from both fights
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](2);
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_2, user1);

        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices1 });
        claims[1] = Booster.ClaimInput({ fightId: FIGHT_2, boostIndices: indices2 });

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        vm.prank(user1);
        booster.claimRewards(EVENT_1, claims);

        // Fight 1: refund 100 ether (cancelled)
        // Fight 2: prizePool = 200 - 200 + 1000 = 1000 ether
        //          user1 gets: stake (200) + winnings (1000 * 4000 / 4000 = 1000) = 1200 ether
        // Total: 100 + 1200 = 1300 ether
        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 1300 ether);
    }

    function test_claimRewards_skipsNoWinners() public {
        _createDefaultEvent();

        // User1 places boosts on multiple fights
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts2);

        // Resolve fight 1 with no winners, fight 2 with winners
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 0, 0);

        // FIGHT_2: user1 wins with 200 ether stake, 20 points
        // sumWinnersStakes = 200 ether, winningPoolTotalShares = 20 * 200 = 4000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_2, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION, 10, 20, 200 ether, 4000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim from both fights - fight 1 should be skipped
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](2);
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_2, user1);

        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices1 });
        claims[1] = Booster.ClaimInput({ fightId: FIGHT_2, boostIndices: indices2 });

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        vm.prank(user1);
        booster.claimRewards(EVENT_1, claims);

        // Only fight 2 pays out: 200 ether
        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 200 ether);
    }

    function test_claimRewards_allCancelled() public {
        _createDefaultEvent();

        // User1 places boosts on multiple fights
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_2, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts2);

        // Cancel both fights
        vm.prank(operator);
        booster.cancelFight(EVENT_1, FIGHT_1);

        vm.prank(operator);
        booster.cancelFight(EVENT_1, FIGHT_2);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim refunds from both fights
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](2);
        uint256[] memory indices1 = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory indices2 = booster.getUserBoostIndices(EVENT_1, FIGHT_2, user1);

        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices1 });
        claims[1] = Booster.ClaimInput({ fightId: FIGHT_2, boostIndices: indices2 });

        uint256 balanceBefore = fp.balanceOf(user1, SEASON_1);

        vm.prank(user1);
        booster.claimRewards(EVENT_1, claims);

        // Both fights refund: 100 + 200 = 300 ether
        assertEq(fp.balanceOf(user1, SEASON_1), balanceBefore + 300 ether);
    }

    function testRevert_claimRewards_emptyInputs() public {
        _createDefaultEvent();

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](0);

        vm.prank(user1);
        vm.expectRevert("no claims");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_eventNotExists() public {
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("event not exists");
        booster.claimRewards("FAKE_EVENT", claims);
    }

    function testRevert_claimRewards_afterDeadline() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 2);

        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 10);
        vm.warp(block.timestamp + 11);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("claim deadline passed");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_notResolved() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Mark event as claim ready (even though fight is not resolved)
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("not resolved");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_invalidFightId() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        claims[0] = Booster.ClaimInput({ fightId: INVALID_FIGHT_ID, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("fightId not in event");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_emptyBoostIndices() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = new uint256[](0);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("no boost indices");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_notOwner() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 2);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user2);
        vm.expectRevert("not boost owner");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_alreadyClaimed() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // user1 wins with 100 ether stake, 20 points
        // sumWinnersStakes = 100 ether, winningPoolTotalShares = 20 * 100 = 2000 ether
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        // Claim first time
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, indices);

        // Try to claim again via claimRewards
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("already claimed");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_loser() public {
        _createDefaultEvent();

        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts);

        // Resolve with BLUE winning
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.BLUE, Booster.WinMethod.KNOCKOUT, 10, 20, 10, 2);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("boost did not win");
        booster.claimRewards(EVENT_1, claims);
    }

    function testRevert_claimRewards_nothingToClaim() public {
        _createDefaultEvent();

        // Resolve fight with no winners
        vm.prank(operator);
        booster.submitFightResult(EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 0, 0);

        // Mark event as claim ready
        _setEventClaimReady(EVENT_1);

        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("nothing to claim");
        booster.claimRewards(EVENT_1, claims);
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
        booster.depositBonus(EVENT_1, FIGHT_1, 500 ether, false);

        // Check totalPool
        assertEq(booster.totalPool(EVENT_1, FIGHT_1), 600 ether);
    }

    // ============ Event Claim Ready Tests ============

    function test_setEventClaimReady() public {
        _createDefaultEvent();

        // Verify event is not claim ready initially
        (,,, bool claimReady) = booster.getEvent(EVENT_1);
        assertFalse(claimReady);

        // Mark event as claim ready
        vm.prank(operator);
        vm.expectEmit(true, false, false, false);
        emit Booster.EventClaimReady(EVENT_1, true);
        booster.setEventClaimReady(EVENT_1, true);

        // Verify event is now claim ready
        (,,, claimReady) = booster.getEvent(EVENT_1);
        assertTrue(claimReady);
        assertTrue(booster.isEventClaimReady(EVENT_1));

        // Test setting it back to false
        vm.prank(operator);
        vm.expectEmit(true, false, false, false);
        emit Booster.EventClaimReady(EVENT_1, false);
        booster.setEventClaimReady(EVENT_1, false);

        // Verify event is no longer claim ready
        (,,, claimReady) = booster.getEvent(EVENT_1);
        assertFalse(claimReady);
        assertFalse(booster.isEventClaimReady(EVENT_1));
    }

    function testRevert_setEventClaimReady_notOperator() public {
        _createDefaultEvent();

        vm.prank(user1);
        vm.expectRevert();
        booster.setEventClaimReady(EVENT_1, true);
    }

    function testRevert_claimReward_notClaimReady() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        // Try to claim without marking event as claim ready
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        vm.prank(user1);
        vm.expectRevert("event not claim ready");
        booster.claimReward(EVENT_1, FIGHT_1, indices);
    }

    function testRevert_claimRewards_notClaimReady() public {
        _createDefaultEvent();
        _placeBoostsAndResolve();

        // Try to claim without marking event as claim ready
        Booster.ClaimInput[] memory claims = new Booster.ClaimInput[](1);
        uint256[] memory indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        claims[0] = Booster.ClaimInput({ fightId: FIGHT_1, boostIndices: indices });

        vm.prank(user1);
        vm.expectRevert("event not claim ready");
        booster.claimRewards(EVENT_1, claims);
    }

    function test_submitFightResult_canUpdateBeforeClaimReady() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        // Submit result first time
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Verify fight is resolved
        (Booster.FightStatus status,,,,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(status), uint256(Booster.FightStatus.RESOLVED));

        // Can update result before event is claim ready
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION, 10, 20, 100 ether, 2000 ether
        );

        // Verify result was updated
        (, Booster.Corner winner, Booster.WinMethod method,,,,,,,,,) = booster.getFight(EVENT_1, FIGHT_1);
        assertEq(uint256(winner), uint256(Booster.Corner.RED));
        assertEq(uint256(method), uint256(Booster.WinMethod.SUBMISSION));
    }

    function testRevert_submitFightResult_cannotUpdateAfterClaimReady() public {
        _createDefaultEvent();
        _placeMultipleBoosts();

        // Submit result
        vm.prank(operator);
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        vm.prank(operator);
        booster.setEventClaimReady(EVENT_1, true);

        // Cannot update result after event is claim ready
        vm.prank(operator);
        vm.expectRevert("event claim ready");
        booster.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.SUBMISSION, 10, 20, 100 ether, 2000 ether
        );
    }

    // ============ Real-world Scenario Tests ============

    function test_realWorldScenario_userNotOnAllowlist() public {
        vm.startPrank(admin);

        // Deploy fresh FP1155 and Booster to simulate mainnet conditions
        FP1155 implementation = new FP1155();
        bytes memory initData =
            abi.encodeWithSelector(FP1155.initialize.selector, "https://api.fightfoundation.io/fp/", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FP1155 fpReal = FP1155(address(proxy));

        // Deploy Booster via ERC1967Proxy and initialize
        Booster boosterImplementation = new Booster();
        bytes memory boosterInitData = abi.encodeWithSelector(Booster.initialize.selector, address(fpReal), admin);
        ERC1967Proxy boosterProxy = new ERC1967Proxy(address(boosterImplementation), boosterInitData);
        Booster boosterReal = Booster(address(boosterProxy));

        // Grant roles like mainnet
        fpReal.grantRole(fpReal.TRANSFER_AGENT_ROLE(), address(boosterReal));
        fpReal.grantRole(fpReal.MINTER_ROLE(), admin);
        boosterReal.grantRole(boosterReal.OPERATOR_ROLE(), admin);

        // Mint tokens to a regular user (NOT on allowlist)
        address regularUser = makeAddr("regularUser");
        fpReal.mint(regularUser, SEASON_1, 10_000 ether, "");

        // Create event
        boosterReal.createEvent(EVENT_1, 3, SEASON_1, 0);

        vm.stopPrank();

        // Regular user (NOT on allowlist) tries to place boost
        vm.prank(regularUser);
        Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
        boosts[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        // This should work because Booster has TRANSFER_AGENT_ROLE
        boosterReal.placeBoosts(EVENT_1, boosts);

        // Verify boost was placed
        assertEq(fpReal.balanceOf(regularUser, SEASON_1), 9900 ether);
        assertEq(fpReal.balanceOf(address(boosterReal), SEASON_1), 100 ether);
    }

    function test_realWorldScenario_claimWithoutAllowlist() public {
        vm.startPrank(admin);

        // Deploy fresh FP1155 and Booster
        FP1155 implementation = new FP1155();
        bytes memory initData =
            abi.encodeWithSelector(FP1155.initialize.selector, "https://api.fightfoundation.io/fp/", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FP1155 fpReal = FP1155(address(proxy));

        // Deploy Booster via ERC1967Proxy and initialize
        Booster boosterImplementation = new Booster();
        bytes memory boosterInitData = abi.encodeWithSelector(Booster.initialize.selector, address(fpReal), admin);
        ERC1967Proxy boosterProxy = new ERC1967Proxy(address(boosterImplementation), boosterInitData);
        Booster boosterReal = Booster(address(boosterProxy));

        // Grant roles - Booster has TRANSFER_AGENT_ROLE
        fpReal.grantRole(fpReal.TRANSFER_AGENT_ROLE(), address(boosterReal));
        fpReal.grantRole(fpReal.MINTER_ROLE(), admin);
        boosterReal.grantRole(boosterReal.OPERATOR_ROLE(), admin);

        // Create two regular users (NOT on allowlist)
        address user1Real = makeAddr("user1Real");
        address user2Real = makeAddr("user2Real");

        fpReal.mint(user1Real, SEASON_1, 10_000 ether, "");
        fpReal.mint(user2Real, SEASON_1, 10_000 ether, "");

        // Create event
        boosterReal.createEvent(EVENT_1, 3, SEASON_1, 0);

        vm.stopPrank();

        // Users place boosts
        vm.prank(user1Real);
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, 100 ether, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);
        boosterReal.placeBoosts(EVENT_1, boosts1);

        vm.prank(user2Real);
        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_1, 200 ether, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);
        boosterReal.placeBoosts(EVENT_1, boosts2);

        // Resolve fight
        vm.prank(admin);
        boosterReal.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 100 ether, 2000 ether
        );

        // Mark event as claim ready
        vm.prank(admin);
        boosterReal.setEventClaimReady(EVENT_1, true);

        // User1 (winner) claims without being on allowlist
        uint256[] memory indices = boosterReal.getUserBoostIndices(EVENT_1, FIGHT_1, user1Real);

        vm.prank(user1Real);
        boosterReal.claimReward(EVENT_1, FIGHT_1, indices);

        // Verify payout: stake (100) + winnings from prize pool (200-100=100 bonus, all goes to user1)
        // prizePool = 300 - 100 + 0 = 200, user gets 200 + 100 = 300
        assertEq(fpReal.balanceOf(user1Real, SEASON_1), 10_000 ether - 100 ether + 300 ether);
    }

    function test_realWorldScenario_multipleUsersNoneOnAllowlist() public {
        vm.startPrank(admin);

        // Deploy fresh contracts
        FP1155 implementation = new FP1155();
        bytes memory initData =
            abi.encodeWithSelector(FP1155.initialize.selector, "https://api.fightfoundation.io/fp/", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        FP1155 fpReal = FP1155(address(proxy));

        // Deploy Booster via ERC1967Proxy and initialize
        Booster boosterImplementation = new Booster();
        bytes memory boosterInitData = abi.encodeWithSelector(Booster.initialize.selector, address(fpReal), admin);
        ERC1967Proxy boosterProxy = new ERC1967Proxy(address(boosterImplementation), boosterInitData);
        Booster boosterReal = Booster(address(boosterProxy));

        // Setup roles
        fpReal.grantRole(fpReal.TRANSFER_AGENT_ROLE(), address(boosterReal));
        fpReal.grantRole(fpReal.MINTER_ROLE(), admin);
        boosterReal.grantRole(boosterReal.OPERATOR_ROLE(), admin);

        // Create 5 regular users
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            fpReal.mint(users[i], SEASON_1, 10_000 ether, "");
        }

        // Create event
        boosterReal.createEvent(EVENT_1, 1, SEASON_1, 0);

        vm.stopPrank();

        // All users place boosts
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            Booster.BoostInput[] memory boosts = new Booster.BoostInput[](1);
            boosts[0] = Booster.BoostInput(
                FIGHT_1,
                (i + 1) * 100 ether,
                i % 2 == 0 ? Booster.Corner.RED : Booster.Corner.BLUE,
                Booster.WinMethod.KNOCKOUT
            );
            boosterReal.placeBoosts(EVENT_1, boosts);
        }

        // Resolve: RED + KNOCKOUT wins (users 0, 2, 4 win)
        // Winners: user0 (100), user2 (300), user4 (500) = 900 ether total
        // Losers: user1 (200), user3 (400) = 600 ether total
        // sumWinnersStakes = 900, winningPoolTotalShares = (20*100) + (20*300) + (20*500) = 18000
        vm.prank(admin);
        boosterReal.submitFightResult(
            EVENT_1, FIGHT_1, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT, 10, 20, 900 ether, 18_000 ether
        );

        // Mark event as claim ready
        vm.prank(admin);
        boosterReal.setEventClaimReady(EVENT_1, true);

        // Winners claim
        uint256 totalPaidOut = 0;
        for (uint256 i = 0; i < 5; i++) {
            if (i % 2 == 0) {
                // Winners
                uint256[] memory indices = boosterReal.getUserBoostIndices(EVENT_1, FIGHT_1, users[i]);
                uint256 balBefore = fpReal.balanceOf(users[i], SEASON_1);

                vm.prank(users[i]);
                boosterReal.claimReward(EVENT_1, FIGHT_1, indices);

                uint256 payout = fpReal.balanceOf(users[i], SEASON_1) - balBefore;
                totalPaidOut += payout;
            }
        }

        // Total pool was 1500 ether, all should be distributed (allow 1 wei rounding error)
        assertApproxEqAbs(totalPaidOut, 1500 ether, 1);
    }

    /**
     * @notice Test verifying the fix for cancelled fight refund accounting bug
     * @dev This test verifies that cancelled fight refunds are correctly reflected in fight.claimedAmount,
     *      allowing purgeEvent to correctly calculate unclaimed funds and transfer the remaining balance
     */
    function test_cancelledFightRefundAccountingBug() public {
        // Setup: Create event and place bets
        _createDefaultEvent();

        uint256 user1Stake = 100 ether;
        uint256 user2Stake = 200 ether;
        uint256 bonusAmount = 300 ether;

        // Users place boosts
        Booster.BoostInput[] memory boosts1 = new Booster.BoostInput[](1);
        boosts1[0] = Booster.BoostInput(FIGHT_1, user1Stake, Booster.Corner.RED, Booster.WinMethod.KNOCKOUT);

        Booster.BoostInput[] memory boosts2 = new Booster.BoostInput[](1);
        boosts2[0] = Booster.BoostInput(FIGHT_1, user2Stake, Booster.Corner.BLUE, Booster.WinMethod.SUBMISSION);

        vm.prank(user1);
        booster.placeBoosts(EVENT_1, boosts1);

        vm.prank(user2);
        booster.placeBoosts(EVENT_1, boosts2);

        // Operator deposits bonus
        vm.prank(operator);
        booster.depositBonus(EVENT_1, FIGHT_1, bonusAmount, false);

        // Verify initial state
        (
            ,,,
            uint256 bonusPool,
            uint256 originalPool,
            uint256 _sumWinnersStakes,
            uint256 _winningPoolTotalShares,
            uint256 _pointsForWinner,
            uint256 _pointsForWinnerMethod,
            uint256 claimedAmount,
            uint256 _boostCutoff,
            bool _cancelled
        ) = booster.getFight(EVENT_1, FIGHT_1);
        uint256 totalPool = originalPool + bonusPool;

        console2.log("Initial state:");
        console2.log("  Original pool: %d", originalPool);
        console2.log("  Bonus pool: %d", bonusPool);
        console2.log("  Total pool: %d", totalPool);
        console2.log("  Claimed amount: %d", claimedAmount);
        console2.log("  Contract balance: %d", fp.balanceOf(address(booster), SEASON_1));

        assertEq(originalPool, user1Stake + user2Stake, "Original pool should equal total stakes");
        assertEq(bonusPool, bonusAmount, "Bonus pool should equal deposited amount");
        assertEq(claimedAmount, 0, "Initially no claims");
        assertEq(totalPool, 600 ether, "Total pool should be 600 ether");

        // STEP 1: Cancel the fight
        vm.prank(operator);
        booster.cancelFight(EVENT_1, FIGHT_1);

        // Mark event as claim ready (required even for refunds)
        _setEventClaimReady(EVENT_1);

        // STEP 2: Users claim refunds
        uint256[] memory user1Indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user1);
        uint256[] memory user2Indices = booster.getUserBoostIndices(EVENT_1, FIGHT_1, user2);

        uint256 contractBalanceBefore = fp.balanceOf(address(booster), SEASON_1);
        uint256 user1BalanceBefore = fp.balanceOf(user1, SEASON_1);
        uint256 user2BalanceBefore = fp.balanceOf(user2, SEASON_1);

        console2.log("\nBefore refunds:");
        console2.log("  Contract balance: %d", contractBalanceBefore);
        console2.log("  User1 balance: %d", user1BalanceBefore);
        console2.log("  User2 balance: %d", user2BalanceBefore);

        // User1 claims refund
        vm.prank(user1);
        booster.claimReward(EVENT_1, FIGHT_1, user1Indices);

        // User2 claims refund
        vm.prank(user2);
        booster.claimReward(EVENT_1, FIGHT_1, user2Indices);

        uint256 contractBalanceAfterRefunds = fp.balanceOf(address(booster), SEASON_1);
        uint256 user1BalanceAfter = fp.balanceOf(user1, SEASON_1);
        uint256 user2BalanceAfter = fp.balanceOf(user2, SEASON_1);

        console2.log("\nAfter refunds:");
        console2.log("  Contract balance: %d", contractBalanceAfterRefunds);
        console2.log("  User1 balance: %d", user1BalanceAfter);
        console2.log("  User2 balance: %d", user2BalanceAfter);

        // Verify refunds were paid correctly
        assertEq(user1BalanceAfter, user1BalanceBefore + user1Stake, "User1 should receive refund");
        assertEq(user2BalanceAfter, user2BalanceBefore + user2Stake, "User2 should receive refund");
        assertEq(
            contractBalanceAfterRefunds,
            contractBalanceBefore - user1Stake - user2Stake,
            "Contract should pay out stakes"
        );

        // STEP 3: Check fight.claimedAmount - BUG FIXED: should be updated now
        (
            ,,,
            uint256 _bonusPool2,
            uint256 _originalPool2,
            uint256 _sumWinnersStakes2,
            uint256 _winningPoolTotalShares2,
            uint256 _pointsForWinner2,
            uint256 _pointsForWinnerMethod2,
            uint256 claimedAmountAfterRefunds,
            uint256 _boostCutoff2,
            bool _cancelled2
        ) = booster.getFight(EVENT_1, FIGHT_1);

        console2.log("\nBug Fix Verification:");
        console2.log("  fight.claimedAmount after refunds: %d", claimedAmountAfterRefunds);
        console2.log("  Expected (bug fixed): %d", user1Stake + user2Stake);
        console2.log("  Actual refunds paid: %d", user1Stake + user2Stake);

        // BUG FIXED: claimedAmount should now be updated correctly
        assertEq(
            claimedAmountAfterRefunds,
            user1Stake + user2Stake,
            "claimedAmount should be updated for cancelled fight refunds"
        );

        // STEP 4: Set claim deadline to enable purging
        vm.prank(operator);
        booster.setEventClaimDeadline(EVENT_1, block.timestamp + 1);

        // Advance time past deadline
        vm.warp(block.timestamp + 2);

        // STEP 5: Attempt to purge - should succeed now that accounting is correct
        console2.log("\nAttempting purgeEvent (should succeed):");
        console2.log("  Remaining contract balance: %d", contractBalanceAfterRefunds);
        console2.log("  purgeEvent will try to sweep: %d", totalPool - claimedAmountAfterRefunds);
        console2.log("  Expected unclaimed: %d (bonus pool)", bonusAmount);

        uint256 operatorBalanceBefore = fp.balanceOf(operator, SEASON_1);

        // This should NOT revert because accounting is now correct
        vm.prank(operator);
        booster.purgeEvent(EVENT_1, operator);

        uint256 operatorBalanceAfter = fp.balanceOf(operator, SEASON_1);

        // Verify operator received the remaining bonus pool
        assertEq(
            operatorBalanceAfter - operatorBalanceBefore, bonusAmount, "Operator should receive remaining bonus pool"
        );
    }
}
