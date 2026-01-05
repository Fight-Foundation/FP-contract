// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { DailyLottery } from "../src/DailyLottery.sol";
import { FP1155 } from "../src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title DailyLotteryTest
 * @notice Comprehensive test suite for DailyLottery contract
 */
contract DailyLotteryTest is Test {
    DailyLottery public lottery;
    FP1155 public fpToken;
    IERC20 public usdt;

    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public freeEntrySigner;

    uint256 public signerPk = 0xBEEF; // Test private key for free entry signer

    uint256 public constant SEASON_ID = 1;
    uint256 public constant INITIAL_FP_BALANCE = 100; // 100 FP per user (ERC1155 has no decimals)
    uint256 public constant PRIZE_AMOUNT_FP = 1000; // 1000 FP tokens (ERC1155 has no decimals)
    uint256 public constant PRIZE_AMOUNT_USDT = 1000; // 1000 USDT (no decimals)

    // Mock USDT token for testing
    MockERC20 public mockUsdt;

    event LotteryRoundCreated(
        uint256 indexed dayId,
        uint256 seasonId,
        uint256 entryPrice,
        uint256 maxEntriesPerUser,
        uint256 maxFreeEntriesPerUser
    );
    event FreeEntryGranted(address indexed user, uint256 indexed dayId, uint256 nonce);
    event EntryPurchased(address indexed user, uint256 indexed dayId, uint256 entriesPurchased);
    event WinnerDrawn(
        uint256 indexed dayId,
        address indexed winner,
        DailyLottery.PrizeType prizeType,
        address tokenAddress,
        uint256 seasonId,
        uint256 amount
    );
    event DefaultsUpdated(
        uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
    );
    event RoundParametersUpdated(
        uint256 indexed dayId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
    );

    function setUp() public {
        // Set realistic timestamp (January 1, 2024)
        vm.warp(1_704_067_200); // Unix timestamp for 2024-01-01 00:00:00 UTC

        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        freeEntrySigner = vm.addr(signerPk);

        // Deploy mock USDT
        mockUsdt = new MockERC20("Mock USDT", "USDT", 0);
        usdt = IERC20(address(mockUsdt));

        // Deploy FP1155
        FP1155 fpImpl = new FP1155();
        bytes memory fpInitData = abi.encodeCall(FP1155.initialize, ("https://api.example.com/token/", admin));
        ERC1967Proxy fpProxy = new ERC1967Proxy(address(fpImpl), fpInitData);
        fpToken = FP1155(address(fpProxy));

        // Deploy DailyLottery
        DailyLottery lotteryImpl = new DailyLottery();
        bytes memory lotteryInitData = abi.encodeCall(DailyLottery.initialize, (address(fpToken), admin, admin));
        ERC1967Proxy lotteryProxy = new ERC1967Proxy(address(lotteryImpl), lotteryInitData);
        lottery = DailyLottery(address(lotteryProxy));

        // Setup roles
        vm.startPrank(admin);
        fpToken.grantRole(fpToken.MINTER_ROLE(), admin);
        fpToken.grantRole(fpToken.TRANSFER_AGENT_ROLE(), address(lottery));
        fpToken.grantRole(fpToken.TRANSFER_AGENT_ROLE(), admin); // Allow admin to transfer FP for prizes
        lottery.grantRole(lottery.FREE_ENTRY_SIGNER_ROLE(), freeEntrySigner);
        vm.stopPrank();

        // Mint initial FP to users
        vm.startPrank(admin);
        fpToken.mint(user1, 324_001, INITIAL_FP_BALANCE, "");
        fpToken.mint(user2, 324_001, INITIAL_FP_BALANCE, "");
        fpToken.mint(user3, 324_001, INITIAL_FP_BALANCE, "");
        fpToken.mint(admin, 324_001, PRIZE_AMOUNT_FP * 5, ""); // For prize pool
        vm.stopPrank();

        // Mint USDT to admin for prize pool
        mockUsdt.mint(admin, PRIZE_AMOUNT_USDT * 5);

        // Approve lottery to spend FP for users and admin
        vm.prank(user1);
        fpToken.setApprovalForAll(address(lottery), true);
        vm.prank(user2);
        fpToken.setApprovalForAll(address(lottery), true);
        vm.prank(user3);
        fpToken.setApprovalForAll(address(lottery), true);

        vm.startPrank(admin);
        fpToken.setApprovalForAll(address(lottery), true);
        mockUsdt.approve(address(lottery), type(uint256).max);
        vm.stopPrank();
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(address(lottery.fpToken()), address(fpToken), "FP token address mismatch");
        assertTrue(lottery.hasRole(lottery.LOTTERY_ADMIN_ROLE(), admin), "Admin should have LOTTERY_ADMIN_ROLE");
        assertEq(lottery.defaultSeasonId(), 324_001, "Default season ID should be 324001");
        assertEq(lottery.defaultEntryPrice(), 1, "Default entry price should be 1");
        assertEq(lottery.defaultMaxEntriesPerUser(), 10, "Default max entries should be 10");
        assertEq(lottery.defaultMaxFreeEntriesPerUser(), 1, "Default max free entries should be 1");
    }

    // ============ Lottery Round Auto-Creation Tests ============
    // createLotteryRound() function removed - rounds are auto-created when users participate

    function test_AutoCreateRound() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round doesn't exist yet
        DailyLottery.LotteryRound memory roundBefore = lottery.getLotteryRound(dayId);
        assertEq(roundBefore.dayId, 0, "Round should not exist yet");

        // User claims free entry - should auto-create round
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit LotteryRoundCreated(dayId, 324_001, 1, 10, 1); // Using defaults: season=324001, price=1, max=10, maxFree=1
        lottery.claimFreeEntry(sig);

        // Round should now exist with defaults
        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.dayId, dayId, "Day ID mismatch");
        assertEq(round.seasonId, 324_001, "Season ID should be default (324001)");
        assertEq(round.entryPrice, 1, "Entry price should be default (1)");
        assertEq(round.maxEntriesPerUser, 10, "Max entries should be default (10)");
        assertEq(round.totalEntries, 1, "Should have 1 entry");
        assertEq(round.totalPaid, 0, "Total paid should be 0 (free entry)");
        // Verify prize fields are initialized with defaults
        assertEq(uint256(round.prizeType), uint256(DailyLottery.PrizeType.FP), "Prize type should default to FP");
        assertEq(round.prizeTokenAddress, address(0), "Prize token address should default to address(0)");
        assertEq(round.prizeSeasonId, 0, "Prize season ID should default to 0");
        assertEq(round.prizeAmount, 0, "Prize amount should default to 0");
    }

    function test_SetDefaults() public {
        // Change defaults
        vm.prank(admin);
        lottery.setDefaults(2, 3, 10, 2);

        assertEq(lottery.defaultSeasonId(), 2, "Default season should be 2");
        assertEq(lottery.defaultEntryPrice(), 3, "Default entry price should be 3");
        assertEq(lottery.defaultMaxEntriesPerUser(), 10, "Default max entries should be 10");
        assertEq(lottery.defaultMaxFreeEntriesPerUser(), 2, "Default max free entries should be 2");

        // New round should use new defaults
        uint256 dayId = block.timestamp / 1 days;
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.seasonId, 2, "Should use new default season");
        assertEq(round.entryPrice, 3, "Should use new default entry price");
        assertEq(round.maxEntriesPerUser, 10, "Should use new default max entries");
        assertEq(round.maxFreeEntriesPerUser, 2, "Should use new default max free entries");
    }

    function test_SetDefaults_RevertZeroEntryPrice() public {
        vm.prank(admin);
        vm.expectRevert("Invalid entry price");
        lottery.setDefaults(1, 0, 5, 1);
    }

    function test_SetDefaults_RevertZeroMaxEntries() public {
        vm.prank(admin);
        vm.expectRevert("Invalid max entries");
        lottery.setDefaults(1, 1, 0, 1);
    }

    function test_SetDefaults_RevertZeroMaxFreeEntries() public {
        vm.prank(admin);
        vm.expectRevert("Invalid max free entries");
        lottery.setDefaults(1, 1, 5, 0);
    }

    function test_SetDefaults_RevertMaxFreeExceedsMax() public {
        vm.prank(admin);
        vm.expectRevert("Max free exceeds max total");
        lottery.setDefaults(1, 1, 5, 6); // maxFree > maxEntries
    }

    function test_SetDefaults_RevertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        lottery.setDefaults(SEASON_ID, 1, 5, 1);
    }

    // ============ Helper Functions for Signatures ============

    function _signFreeEntry(address account, uint256 dayId, uint256 nonce) internal view returns (bytes memory sig) {
        bytes32 typehash = lottery.FREE_ENTRY_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(typehash, account, dayId, nonce));
        bytes32 digest = MessageHashUtils.toTypedDataHash(lottery.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // ============ Free Entry Tests ============

    function test_ClaimFreeEntry() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Generate signature for free entry (specific to this day)
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        // Claim free entry with signature
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit FreeEntryGranted(user1, dayId, nonce);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(dayId, user1), 1, "User should have 1 entry");
        assertEq(lottery.getTotalEntries(dayId), 1, "Total entries should be 1");
        assertEq(lottery.getUserNonce(dayId, user1), nonce + 1, "Nonce should increment");
    }

    function test_ClaimFreeEntry_RevertInvalidSignature() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Generate signature with wrong private key (not the signer)
        uint256 wrongPk = 0xDEAD;
        uint256 nonce = lottery.getUserNonce(dayId, user1);

        bytes32 typehash = lottery.FREE_ENTRY_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(typehash, user1, dayId, nonce));
        bytes32 digest = MessageHashUtils.toTypedDataHash(lottery.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        // Try to claim free entry with invalid signature
        vm.prank(user1);
        vm.expectRevert("Invalid signer");
        lottery.claimFreeEntry(badSig);
    }

    function test_ClaimFreeEntry_RevertWrongDay() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will auto-create when claiming

        // Generate signature for tomorrow (wrong day)
        uint256 wrongDayId = dayId + 1;
        uint256 nonce = lottery.getUserNonce(wrongDayId, user1);
        bytes memory sig = _signFreeEntry(user1, wrongDayId, nonce);

        // Try to claim with signature for wrong day
        vm.prank(user1);
        vm.expectRevert("Invalid signer");
        lottery.claimFreeEntry(sig);
    }

    function test_ClaimFreeEntry_Multiple() public {
        // Change defaults to allow 2 free entries
        vm.prank(admin);
        lottery.setDefaults(1, 1, 5, 2);

        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Claim first free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(dayId, user1), 1, "User should have 1 entry");

        // Claim second free entry with new signature (new nonce)
        uint256 newNonce = lottery.getUserNonce(dayId, user1);
        bytes memory newSig = _signFreeEntry(user1, dayId, newNonce);

        vm.prank(user1);
        lottery.claimFreeEntry(newSig);

        assertEq(lottery.getUserEntries(dayId, user1), 2, "User should have 2 entries");
        assertEq(lottery.getTotalEntries(dayId), 2, "Total entries should be 2");
    }

    function test_ClaimFreeEntry_RevertMaxFreeEntriesExceeded() public {
        uint256 dayId = block.timestamp / 1 days;

        // Claim first free entry (default max is 1)
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(dayId, user1), 1, "User should have 1 entry");
        assertEq(lottery.getUserNonce(dayId, user1), 1, "Nonce should be 1");

        // Try to claim second free entry - should fail as max is 1
        uint256 newNonce = lottery.getUserNonce(dayId, user1);
        bytes memory newSig = _signFreeEntry(user1, dayId, newNonce);

        vm.prank(user1);
        vm.expectRevert("Max free entries exceeded");
        lottery.claimFreeEntry(newSig);
    }

    function test_ClaimFreeEntry_CanBuyAfterMaxFreeEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Claim free entry (reaches max free entries of 1)
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(dayId, user1), 1, "User should have 1 entry");

        // User can still buy entries after reaching max free entries
        vm.prank(user1);
        lottery.buyEntry();

        assertEq(lottery.getUserEntries(dayId, user1), 2, "User should have 2 entries total");
    }

    // ============ Buy Entries Tests ============

    function test_BuyEntry() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Claim free entry with signature
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        uint256 balanceBefore = fpToken.balanceOf(user1, 324_001);

        // Buy 2 more entries (one at a time)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit EntryPurchased(user1, dayId, 1);
        lottery.buyEntry();

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit EntryPurchased(user1, dayId, 1);
        lottery.buyEntry();

        assertEq(lottery.getUserEntries(dayId, user1), 3, "User should have 3 entries");
        assertEq(lottery.getTotalEntries(dayId), 3, "Total entries should be 3");

        uint256 balanceAfter = fpToken.balanceOf(user1, 324_001);
        assertEq(balanceBefore - balanceAfter, 2, "Should burn 2 FP (2 entries * 1 price)");

        // Verify totalPaid tracks the paid entries (2 entries * 1 price = 2)
        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.totalPaid, 2, "Total paid should be 2 FP (2 entries purchased)");
    }

    function test_BuyEntry_MaxEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Buy maximum entries without free entry (10 total, one at a time)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        assertEq(lottery.getUserEntries(dayId, user1), 10, "User should have 10 entries");

        // Verify totalPaid (10 entries * 1 price = 10)
        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.totalPaid, 10, "Total paid should be 10 FP (10 entries purchased)");

        // Try to claim free entry - should fail as already at max
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        vm.expectRevert("Max entries exceeded");
        lottery.claimFreeEntry(sig);
    }

    function test_BuyEntry_RevertAtMaximum() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Buy 10 entries (maximum)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        assertEq(lottery.getUserEntries(dayId, user1), 10, "User should have 10 entries");

        // Try to buy one more - should fail
        vm.prank(user1);
        vm.expectRevert("Max entries exceeded");
        lottery.buyEntry();
    }

    function test_BuyEntry_RevertExceedsMaximum() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Claim free entry with signature
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Buy 9 more entries to reach max
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        // Try to buy one more entry - should fail as already at max
        vm.prank(user1);
        vm.expectRevert("Max entries exceeded");
        lottery.buyEntry(); // Already have 10, trying to add 1 more = 11 total
    }

    function test_BuyEntry_WithoutFreeEntry() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // User can buy entries without claiming free entry first (3 entries, one at a time)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        assertEq(lottery.getUserEntries(dayId, user1), 3, "User should have 3 entries");

        // Verify totalPaid (3 entries * 1 price = 3)
        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.totalPaid, 3, "Total paid should be 3 FP (3 entries purchased)");

        // User can still claim free entry later
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(dayId, user1), 4, "User should have 4 entries total");
    }

    function test_FreeEntry_AfterBuying() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // User buys 7 entries first (one at a time)
        for (uint256 i = 0; i < 7; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        // Then claims free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Then buys 2 more (total 10)
        vm.prank(user1);
        lottery.buyEntry();
        vm.prank(user1);
        lottery.buyEntry();

        assertEq(lottery.getUserEntries(dayId, user1), 10, "User should have 10 entries total");

        // Try to buy more - should fail
        vm.prank(user1);
        vm.expectRevert("Max entries exceeded");
        lottery.buyEntry();
    }

    // ============ Winner Drawing Tests ============

    function test_DrawWinner_FP() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Setup users with entries
        setupThreeUsersWithEntries();

        uint256 winningIndex = 0; // Pick first entry for testing

        address expectedWinner = lottery.getEntry(dayId, winningIndex);
        uint256 winnerBalanceBefore = fpToken.balanceOf(expectedWinner, 324_001);
        uint256 adminBalanceBefore = fpToken.balanceOf(admin, 324_001);

        // Draw winner (admin transfers prize directly)
        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        lottery.drawWinner(dayId, winningIndex, prize);

        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertTrue(round.finalized, "Round should be finalized");
        assertTrue(round.winner != address(0), "Winner should be set");
        assertEq(round.winner, expectedWinner, "Winner should match entry at index");

        // Verify prize data is stored
        assertEq(uint256(round.prizeType), uint256(DailyLottery.PrizeType.FP), "Prize type should be FP");
        assertEq(round.prizeTokenAddress, address(0), "Prize token address should be address(0) for FP");
        assertEq(round.prizeSeasonId, 324_001, "Prize season ID should match");
        assertEq(round.prizeAmount, PRIZE_AMOUNT_FP, "Prize amount should match");

        // Verify prize was transferred from admin to winner
        uint256 winnerBalanceAfter = fpToken.balanceOf(expectedWinner, 324_001);
        uint256 adminBalanceAfter = fpToken.balanceOf(admin, 324_001);
        assertEq(winnerBalanceAfter - winnerBalanceBefore, PRIZE_AMOUNT_FP, "Winner should have received prize");
        assertEq(adminBalanceBefore - adminBalanceAfter, PRIZE_AMOUNT_FP, "Admin should have sent prize");
    }

    function test_DrawWinner_ERC20() public {
        uint256 dayId = block.timestamp / 1 days;

        // Setup users with entries (round will auto-create)
        setupThreeUsersWithEntries();

        uint256 winningIndex = 2; // Pick third entry for testing

        address expectedWinner = lottery.getEntry(dayId, winningIndex);
        uint256 winnerBalanceBefore = usdt.balanceOf(expectedWinner);
        uint256 adminBalanceBefore = usdt.balanceOf(admin);

        // Draw winner (admin transfers ERC20 prize directly)
        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.ERC20, tokenAddress: address(usdt), seasonId: 0, amount: PRIZE_AMOUNT_USDT
        });

        vm.prank(admin);
        lottery.drawWinner(dayId, winningIndex, prize);

        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertTrue(round.finalized, "Round should be finalized");
        assertEq(round.winner, expectedWinner, "Winner should match entry at index");

        // Verify prize data is stored
        assertEq(uint256(round.prizeType), uint256(DailyLottery.PrizeType.ERC20), "Prize type should be ERC20");
        assertEq(round.prizeTokenAddress, address(usdt), "Prize token address should be USDT address");
        assertEq(round.prizeSeasonId, 0, "Prize season ID should be 0 for ERC20");
        assertEq(round.prizeAmount, PRIZE_AMOUNT_USDT, "Prize amount should match");

        // Verify ERC20 prize was transferred from admin to winner
        uint256 winnerBalanceAfter = usdt.balanceOf(expectedWinner);
        uint256 adminBalanceAfter = usdt.balanceOf(admin);
        assertEq(winnerBalanceAfter - winnerBalanceBefore, PRIZE_AMOUNT_USDT, "Winner should have received ERC20 prize");
        assertEq(adminBalanceBefore - adminBalanceAfter, PRIZE_AMOUNT_USDT, "Admin should have sent ERC20 prize");
    }

    function test_DrawWinner_RevertNoEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round doesn't exist yet (not auto-created since no user participated)
        // Expect LotteryNotActive error instead of NoEntries
        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        vm.expectRevert("Lottery not active");
        lottery.drawWinner(dayId, 0, prize);
    }

    function test_DrawWinner_RevertAlreadyFinalized() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Setup users with entries
        setupThreeUsersWithEntries();

        // Draw winner
        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        lottery.drawWinner(dayId, 0, prize);

        // Try to draw again
        vm.prank(admin);
        vm.expectRevert("Already finalized");
        lottery.drawWinner(dayId, 0, prize);
    }

    function test_DrawWinner_RevertInvalidIndex() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Setup users with entries (6 total entries)
        setupThreeUsersWithEntries();

        uint256 totalEntries = lottery.getTotalEntries(dayId);

        // Try to draw with invalid index (>= totalEntries)
        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        vm.expectRevert("Invalid winning index");
        lottery.drawWinner(dayId, totalEntries, prize); // Index starts at 0, so totalEntries is out of bounds
    }

    // ============ Multi-Day Tests ============

    function test_MultipleDays() public {
        uint256 day1 = block.timestamp / 1 days;

        // Day 1 lottery (auto-created when users participate)
        setupThreeUsersWithEntries();

        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        lottery.drawWinner(day1, 0, prize);

        // Move to next day
        vm.warp(block.timestamp + 1 days);
        uint256 day2 = lottery.getCurrentDayId(); // Use the contract's calculation to ensure consistency

        // Day 2 lottery (auto-created when users participate)
        // Users need to claim again on day 2 (new signature for new day)
        uint256 nonce = lottery.getUserNonce(day2, user1);
        bytes memory sig = _signFreeEntry(user1, day2, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        assertEq(lottery.getUserEntries(day2, user1), 1, "User should have 1 entry on day 2");
        assertEq(
            lottery.getUserEntries(day1, user1), 3, "User should still have 3 entries from day 1 (separate from day 2)"
        );
    }

    // ============ View Function Tests ============

    function test_GetCurrentDayId() public view {
        uint256 expectedDayId = block.timestamp / 1 days;
        assertEq(lottery.getCurrentDayId(), expectedDayId, "Current day ID mismatch");
    }

    function test_GetEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Round will be auto-created when claiming free entry

        // Add entries from multiple users
        uint256 nonce1 = lottery.getUserNonce(dayId, user1);
        bytes memory sig1 = _signFreeEntry(user1, dayId, nonce1);
        vm.prank(user1);
        lottery.claimFreeEntry(sig1);

        uint256 nonce2 = lottery.getUserNonce(dayId, user2);
        bytes memory sig2 = _signFreeEntry(user2, dayId, nonce2);
        vm.prank(user2);
        lottery.claimFreeEntry(sig2);

        // Verify entries using getEntry and getTotalEntries
        assertEq(lottery.getTotalEntries(dayId), 2, "Should have 2 entries");
        assertEq(lottery.getEntry(dayId, 0), user1, "First entry should be user1");
        assertEq(lottery.getEntry(dayId, 1), user2, "Second entry should be user2");
    }

    function test_GetRemainingEntries_NoEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Check remaining entries before any participation
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 1, "Should have 1 free entry available (default)");
        assertEq(remainingTotal, 10, "Should have 10 total entries available (default)");
    }

    function test_GetRemainingEntries_AfterFreeEntry() public {
        uint256 dayId = block.timestamp / 1 days;

        // Claim free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Check remaining entries
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 0, "Should have 0 free entries remaining");
        assertEq(remainingTotal, 9, "Should have 9 total entries remaining");
    }

    function test_GetRemainingEntries_AfterBuyingEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Buy 3 entries
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        // Check remaining entries
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 1, "Should still have 1 free entry available");
        assertEq(remainingTotal, 7, "Should have 7 total entries remaining");
    }

    function test_GetRemainingEntries_AfterMixedEntries() public {
        uint256 dayId = block.timestamp / 1 days;

        // Claim free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Buy 2 more entries
        vm.prank(user1);
        lottery.buyEntry();
        vm.prank(user1);
        lottery.buyEntry();

        // Check remaining entries (total 3 entries used: 1 free + 2 paid)
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 0, "Should have 0 free entries remaining");
        assertEq(remainingTotal, 7, "Should have 7 total entries remaining");
    }

    function test_GetRemainingEntries_AtMaximum() public {
        uint256 dayId = block.timestamp / 1 days;

        // Claim free entry and buy 9 more to reach max (10 total)
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        for (uint256 i = 0; i < 9; i++) {
            vm.prank(user1);
            lottery.buyEntry();
        }

        // Check remaining entries
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 0, "Should have 0 free entries remaining");
        assertEq(remainingTotal, 0, "Should have 0 total entries remaining");
    }

    function test_GetRemainingEntries_WithCustomDefaults() public {
        // Change defaults to 2 free entries out of 10 total
        vm.prank(admin);
        lottery.setDefaults(1, 1, 10, 2);

        uint256 dayId = block.timestamp / 1 days;

        // Check remaining entries before any participation
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 2, "Should have 2 free entries available (new default)");
        assertEq(remainingTotal, 10, "Should have 10 total entries available (new default)");

        // Claim one free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Check remaining entries again
        (remainingFree, remainingTotal) = lottery.getRemainingEntries(dayId, user1);

        assertEq(remainingFree, 1, "Should have 1 free entry remaining");
        assertEq(remainingTotal, 9, "Should have 9 total entries remaining");
    }

    function test_GetRemainingEntries_NonExistentRound() public {
        // Move to future day that has no round yet
        vm.warp(block.timestamp + 5 days);
        uint256 futureDayId = lottery.getCurrentDayId();

        // Check remaining entries for non-existent round (should use defaults)
        (uint256 remainingFree, uint256 remainingTotal) = lottery.getRemainingEntries(futureDayId, user1);

        assertEq(remainingFree, 1, "Should use default free entries (1)");
        assertEq(remainingTotal, 10, "Should use default total entries (10)");
    }

    // ============ Helper Functions ============

    function setupThreeUsersWithEntries() internal {
        uint256 dayId = block.timestamp / 1 days;

        // Claim free entries with signatures
        uint256 nonce1 = lottery.getUserNonce(dayId, user1);
        bytes memory sig1 = _signFreeEntry(user1, dayId, nonce1);
        vm.prank(user1);
        lottery.claimFreeEntry(sig1);

        uint256 nonce2 = lottery.getUserNonce(dayId, user2);
        bytes memory sig2 = _signFreeEntry(user2, dayId, nonce2);
        vm.prank(user2);
        lottery.claimFreeEntry(sig2);

        uint256 nonce3 = lottery.getUserNonce(dayId, user3);
        bytes memory sig3 = _signFreeEntry(user3, dayId, nonce3);
        vm.prank(user3);
        lottery.claimFreeEntry(sig3);

        // User1 buys 2 more entries (3 total, one at a time)
        vm.prank(user1);
        lottery.buyEntry();
        vm.prank(user1);
        lottery.buyEntry();

        // User2 buys 1 more entry (2 total)
        vm.prank(user2);
        lottery.buyEntry();

        // User3 keeps just the free entry (1 total)
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        // Pause lottery
        vm.prank(admin);
        lottery.pause();

        // Try to claim free entry while paused
        uint256 dayId = block.timestamp / 1 days;
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        vm.expectRevert();
        lottery.claimFreeEntry(sig);

        // Try to buy entry while paused
        vm.prank(user2);
        vm.expectRevert();
        lottery.buyEntry();
    }

    function test_Unpause() public {
        // Pause then unpause
        vm.startPrank(admin);
        lottery.pause();
        lottery.unpause();
        vm.stopPrank();

        // Should be able to claim free entry after unpause
        uint256 dayId = block.timestamp / 1 days;
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);

        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Should be able to buy entry after unpause
        vm.prank(user2);
        lottery.buyEntry();

        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.totalEntries, 2, "Should have 2 entries");
    }

    function test_Pause_RevertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        lottery.pause();
    }

    function test_Unpause_RevertUnauthorized() public {
        vm.prank(admin);
        lottery.pause();

        vm.prank(user1);
        vm.expectRevert();
        lottery.unpause();
    }

    // ============ Update Round Parameters Tests ============

    function test_UpdateRoundParameters() public {
        uint256 dayId = block.timestamp / 1 days;

        // Create round by claiming entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Buy entry with original price (1 FP)
        uint256 balanceBeforeUpdate = fpToken.balanceOf(user1, 324_001);
        vm.prank(user1);
        lottery.buyEntry();
        uint256 balanceAfterUpdate = fpToken.balanceOf(user1, 324_001);
        assertEq(balanceBeforeUpdate - balanceAfterUpdate, 1, "Should burn 1 FP with original price");

        // Verify user has 2 entries now
        assertEq(lottery.getUserEntries(dayId, user1), 2, "User should have 2 entries");

        // Update round parameters
        uint256 newEntryPrice = 3;
        uint256 newMaxEntriesPerUser = 10;
        uint256 newMaxFreeEntriesPerUser = 3;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoundParametersUpdated(dayId, newEntryPrice, newMaxEntriesPerUser, newMaxFreeEntriesPerUser);
        lottery.updateRoundParameters(dayId, newEntryPrice, newMaxEntriesPerUser, newMaxFreeEntriesPerUser);

        // Verify parameters were updated
        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertEq(round.entryPrice, newEntryPrice, "Entry price should be updated");
        assertEq(round.maxEntriesPerUser, newMaxEntriesPerUser, "Max entries should be updated");
        assertEq(round.maxFreeEntriesPerUser, newMaxFreeEntriesPerUser, "Max free entries should be updated");

        // Buy another entry with new price (3 FP)
        uint256 balanceBeforeNewPrice = fpToken.balanceOf(user1, 324_001);
        vm.prank(user1);
        lottery.buyEntry();
        uint256 balanceAfterNewPrice = fpToken.balanceOf(user1, 324_001);
        assertEq(balanceBeforeNewPrice - balanceAfterNewPrice, 3, "Should burn 3 FP with new price");

        // Verify user has 3 entries total
        assertEq(lottery.getUserEntries(dayId, user1), 3, "User should have 3 entries total");
        assertEq(lottery.getTotalEntries(dayId), 3, "Total entries should be 3");

        // Verify total paid reflects both prices: 1 (old) + 3 (new) = 4 FP
        round = lottery.getLotteryRound(dayId);
        assertEq(round.totalPaid, 4, "Total paid should be 4 FP (1 + 3)");
    }

    function test_UpdateRoundParameters_RevertNonExistentRound() public {
        uint256 futureDayId = (block.timestamp / 1 days) + 10; // Future day

        vm.prank(admin);
        vm.expectRevert("Round does not exist");
        lottery.updateRoundParameters(futureDayId, 2, 8, 2);
    }

    function test_UpdateRoundParameters_RevertFinalizedRound() public {
        uint256 dayId = block.timestamp / 1 days;

        // Create round and finalize it
        setupThreeUsersWithEntries();

        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.FP, tokenAddress: address(0), seasonId: 324_001, amount: PRIZE_AMOUNT_FP
        });

        vm.prank(admin);
        lottery.drawWinner(dayId, 0, prize);

        // Try to update finalized round
        vm.prank(admin);
        vm.expectRevert("Cannot update finalized round");
        lottery.updateRoundParameters(dayId, 2, 8, 2);
    }

    function test_UpdateRoundParameters_RevertInvalidParameters() public {
        uint256 dayId = block.timestamp / 1 days;

        // Create round
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Test zero entry price
        vm.prank(admin);
        vm.expectRevert("Invalid entry price");
        lottery.updateRoundParameters(dayId, 0, 5, 1);

        // Test zero max entries
        vm.prank(admin);
        vm.expectRevert("Invalid max entries");
        lottery.updateRoundParameters(dayId, 1, 0, 1);

        // Test zero max free entries
        vm.prank(admin);
        vm.expectRevert("Invalid max free entries");
        lottery.updateRoundParameters(dayId, 1, 5, 0);

        // Test max free exceeds max total
        vm.prank(admin);
        vm.expectRevert("Max free exceeds max total");
        lottery.updateRoundParameters(dayId, 1, 5, 6);
    }

    function test_UpdateRoundParameters_RevertUnauthorized() public {
        uint256 dayId = block.timestamp / 1 days;

        // Create round
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Try to update with non-admin user
        vm.prank(user1);
        vm.expectRevert();
        lottery.updateRoundParameters(dayId, 2, 8, 2);
    }

    function test_DrawWinner_DifferentERC20Tokens() public {
        uint256 dayId = block.timestamp / 1 days;

        // Setup users with entries (round will auto-create)
        setupThreeUsersWithEntries();

        // Deploy a second ERC20 token (e.g., USDC)
        MockERC20 mockUsdc = new MockERC20("Mock USDC", "USDC", 6);
        IERC20 usdc = IERC20(address(mockUsdc));

        // Mint USDC to admin
        mockUsdc.mint(admin, 1000 * 10 ** 6); // 1000 USDC with 6 decimals

        // Approve USDC for lottery
        vm.prank(admin);
        usdc.approve(address(lottery), type(uint256).max);

        uint256 winningIndex = 1;
        address expectedWinner = lottery.getEntry(dayId, winningIndex);

        // Draw winner with USDC (different from the USDT in setUp)
        uint256 usdcPrizeAmount = 500 * 10 ** 6; // 500 USDC
        uint256 winnerBalanceBefore = usdc.balanceOf(expectedWinner);

        DailyLottery.PrizeData memory usdcPrize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.ERC20, tokenAddress: address(usdc), seasonId: 0, amount: usdcPrizeAmount
        });

        vm.prank(admin);
        lottery.drawWinner(dayId, winningIndex, usdcPrize);

        // Verify USDC prize was transferred
        uint256 winnerBalanceAfter = usdc.balanceOf(expectedWinner);
        assertEq(winnerBalanceAfter - winnerBalanceBefore, usdcPrizeAmount, "Winner should have received USDC");

        // Move to next day and test with yet another token
        vm.warp(block.timestamp + 1 days);
        uint256 day2 = lottery.getCurrentDayId();

        // User claims entry for day 2
        uint256 nonce = lottery.getUserNonce(day2, user1);
        bytes memory sig = _signFreeEntry(user1, day2, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Deploy another ERC20 token (e.g., POL)
        MockERC20 mockPol = new MockERC20("Mock POL", "POL", 18);
        IERC20 pol = IERC20(address(mockPol));

        // Mint POL to admin
        mockPol.mint(admin, 10_000 ether);

        // Approve POL for lottery
        vm.prank(admin);
        pol.approve(address(lottery), type(uint256).max);

        // Draw winner with POL on day 2
        uint256 polPrizeAmount = 1000 ether;
        uint256 user1BalanceBefore = pol.balanceOf(user1);

        DailyLottery.PrizeData memory polPrize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.ERC20, tokenAddress: address(pol), seasonId: 0, amount: polPrizeAmount
        });

        vm.prank(admin);
        lottery.drawWinner(day2, 0, polPrize);

        // Verify POL prize was transferred
        uint256 user1BalanceAfter = pol.balanceOf(user1);
        assertEq(user1BalanceAfter - user1BalanceBefore, polPrizeAmount, "Winner should have received POL");
    }

    function test_DrawWinner_WorksWhilePaused() public {
        uint256 dayId = block.timestamp / 1 days;

        // User claims free entry
        uint256 nonce = lottery.getUserNonce(dayId, user1);
        bytes memory sig = _signFreeEntry(user1, dayId, nonce);
        vm.prank(user1);
        lottery.claimFreeEntry(sig);

        // Pause lottery
        vm.prank(admin);
        lottery.pause();

        // Admin should still be able to draw winner while paused
        uint256 winningIndex = 0;

        // Approve ERC20 token for prize
        vm.prank(admin);
        usdt.approve(address(lottery), PRIZE_AMOUNT_USDT);

        DailyLottery.PrizeData memory prize = DailyLottery.PrizeData({
            prizeType: DailyLottery.PrizeType.ERC20, tokenAddress: address(usdt), seasonId: 0, amount: PRIZE_AMOUNT_USDT
        });

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit WinnerDrawn(dayId, user1, DailyLottery.PrizeType.ERC20, address(usdt), 0, PRIZE_AMOUNT_USDT);
        lottery.drawWinner(dayId, winningIndex, prize);

        DailyLottery.LotteryRound memory round = lottery.getLotteryRound(dayId);
        assertTrue(round.finalized, "Round should be finalized");
        assertEq(round.winner, user1, "Winner should be user1");
    }
}

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }
}

