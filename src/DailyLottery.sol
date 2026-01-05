// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { FP1155 } from "./FP1155.sol";

/**
 * @title DailyLottery
 * @notice Daily lottery system where users can get free entries via backend authorization.
 *         Users can also buy additional entries using FP tokens.
 *         Free entries per user are capped at maxFreeEntriesPerUser (default 1).
 *         Total entries per user are capped at maxEntriesPerUser (default 5).
 *         Prize can be in FP or any ERC20 token, configurable per lottery round.
 * @dev Free entries are authorized via EIP-712 signatures, similar to FP1155 claims.
 *      Users can claim multiple free entries if the backend provides multiple signatures
 *      up to the maxFreeEntriesPerUser limit.
 */
contract DailyLottery is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;

    // ============ Roles ============
    bytes32 public constant LOTTERY_ADMIN_ROLE = keccak256("LOTTERY_ADMIN_ROLE");
    bytes32 public constant FREE_ENTRY_SIGNER_ROLE = keccak256("FREE_ENTRY_SIGNER_ROLE");

    // ============ Constants ============

    // EIP-712 typehash for free entry authorization
    bytes32 public constant FREE_ENTRY_TYPEHASH = keccak256("FreeEntry(address account,uint256 dayId,uint256 nonce)");

    // ============ Types ============
    enum PrizeType {
        FP,
        ERC20
    }

    struct PrizeData {
        PrizeType prizeType; // Type of prize (FP or ERC20)
        address tokenAddress; // ERC20 token address (only for ERC20 prizes)
        uint256 seasonId; // FP season ID (only for FP prizes)
        uint256 amount; // Amount of prize
    }

    struct LotteryRound {
        uint256 dayId; // Day identifier (e.g., block.timestamp / 1 day)
        uint256 seasonId; // FP season ID for this round (used for burning tokens)
        uint256 entryPrice; // Price in FP to buy one entry (in FP token decimals, default 1)
        uint256 maxEntriesPerUser; // Maximum entries per user for this round (default 5)
        uint256 maxFreeEntriesPerUser; // Maximum free entries per user for this round (default 1)
        uint256 totalEntries; // Total number of entries
        uint256 totalPaid; // Total FP tokens paid/burned for this round
        address winner; // Winner address (address(0) if not drawn yet) - packed with finalized
        bool finalized; // Whether the round has been finalized - packed with winner
        PrizeType prizeType; // Type of prize awarded (FP or ERC20)
        address prizeTokenAddress; // ERC20 token address (only for ERC20 prizes, address(0) for FP)
        uint256 prizeSeasonId; // FP season ID (only for FP prizes, 0 for ERC20)
        uint256 prizeAmount; // Amount of prize awarded
    }

    // ============ Storage ============
    FP1155 public fpToken; // FP1155 token contract

    // Default values for auto-created rounds
    uint256 public defaultSeasonId; // Default season ID for FP
    uint256 public defaultEntryPrice; // Default entry price (1 by default)
    uint256 public defaultMaxEntriesPerUser; // Default max entries per user (5 by default)
    uint256 public defaultMaxFreeEntriesPerUser; // Default max free entries per user (1 by default)

    // Lottery rounds by day
    mapping(uint256 => LotteryRound) private lotteryRounds;

    // User entries per day: dayId => user => entry count
    mapping(uint256 => mapping(address => uint256)) private userEntries;

    // Entry tickets: dayId => array of user addresses (one address per entry)
    mapping(uint256 => address[]) private entries;

    // Nonces for free entry claims (per-user per-round monotonically increasing nonce)
    // dayId => user => nonce
    mapping(uint256 => mapping(address => uint256)) private nonces;

    // ============ Events ============
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
        PrizeType prizeType,
        address tokenAddress, // ERC20 token address (address(0) for FP prizes)
        uint256 seasonId, // FP season ID (0 for ERC20 prizes)
        uint256 amount
    );
    event DefaultsUpdated(
        uint256 seasonId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
    );
    event RoundParametersUpdated(
        uint256 indexed dayId, uint256 entryPrice, uint256 maxEntriesPerUser, uint256 maxFreeEntriesPerUser
    );

    // ============ Initializer ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the DailyLottery contract
     * @param _fpToken Address of the FP1155 token contract
     * @param _admin Address of the admin
     */
    function initialize(address _fpToken, address _admin) public initializer {
        require(_fpToken != address(0) && _admin != address(0), "Invalid address");

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __EIP712_init("DailyLottery", "1");

        fpToken = FP1155(_fpToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(LOTTERY_ADMIN_ROLE, _admin);
        _grantRole(FREE_ENTRY_SIGNER_ROLE, _admin);

        // Set default values for auto-created rounds
        defaultSeasonId = 1;
        defaultEntryPrice = 1;
        defaultMaxEntriesPerUser = 5;
        defaultMaxFreeEntriesPerUser = 1;
    }

    /// @dev UUPS upgrade authorization: only DEFAULT_ADMIN_ROLE can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    // ============ Admin Functions ============

    /**
     * @notice Pause the lottery (stops users from participating)
     * @dev Admin can still draw winners for existing rounds while paused
     */
    function pause() external onlyRole(LOTTERY_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the lottery (allows users to participate again)
     */
    function unpause() external onlyRole(LOTTERY_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Set default values for auto-created lottery rounds
     * @param _defaultSeasonId Default season ID for FP
     * @param _defaultEntryPrice Default entry price
     * @param _defaultMaxEntriesPerUser Default max entries per user
     * @param _defaultMaxFreeEntriesPerUser Default max free entries per user
     */
    function setDefaults(
        uint256 _defaultSeasonId,
        uint256 _defaultEntryPrice,
        uint256 _defaultMaxEntriesPerUser,
        uint256 _defaultMaxFreeEntriesPerUser
    ) external onlyRole(LOTTERY_ADMIN_ROLE) {
        require(_defaultEntryPrice > 0, "Invalid entry price");
        require(_defaultMaxEntriesPerUser > 0, "Invalid max entries");
        require(_defaultMaxFreeEntriesPerUser > 0, "Invalid max free entries");
        require(_defaultMaxFreeEntriesPerUser <= _defaultMaxEntriesPerUser, "Max free exceeds max total");

        defaultSeasonId = _defaultSeasonId;
        defaultEntryPrice = _defaultEntryPrice;
        defaultMaxEntriesPerUser = _defaultMaxEntriesPerUser;
        defaultMaxFreeEntriesPerUser = _defaultMaxFreeEntriesPerUser;

        emit DefaultsUpdated(
            _defaultSeasonId, _defaultEntryPrice, _defaultMaxEntriesPerUser, _defaultMaxFreeEntriesPerUser
        );
    }

    /**
     * @notice Update parameters for an existing lottery round
     * @param dayId Day identifier of the round to update
     * @param newEntryPrice New entry price in FP tokens
     * @param newMaxEntriesPerUser New maximum entries per user
     * @param newMaxFreeEntriesPerUser New maximum free entries per user
     * @dev Only works for rounds that exist and haven't been finalized yet
     */
    function updateRoundParameters(
        uint256 dayId,
        uint256 newEntryPrice,
        uint256 newMaxEntriesPerUser,
        uint256 newMaxFreeEntriesPerUser
    ) external onlyRole(LOTTERY_ADMIN_ROLE) {
        LotteryRound storage round = lotteryRounds[dayId];

        // Validate round exists and is not finalized
        require(round.dayId == dayId, "Round does not exist");
        require(!round.finalized, "Cannot update finalized round");

        // Validate new parameters
        require(newEntryPrice > 0, "Invalid entry price");
        require(newMaxEntriesPerUser > 0, "Invalid max entries");
        require(newMaxFreeEntriesPerUser > 0, "Invalid max free entries");
        require(newMaxFreeEntriesPerUser <= newMaxEntriesPerUser, "Max free exceeds max total");

        // Update parameters
        round.entryPrice = newEntryPrice;
        round.maxEntriesPerUser = newMaxEntriesPerUser;
        round.maxFreeEntriesPerUser = newMaxFreeEntriesPerUser;

        emit RoundParametersUpdated(dayId, newEntryPrice, newMaxEntriesPerUser, newMaxFreeEntriesPerUser);
    }

    /**
     * @notice Internal function to create a lottery round
     * @dev Used by auto-creation when users participate
     */
    function _createRound(
        uint256 dayId,
        uint256 seasonId,
        uint256 entryPrice,
        uint256 maxEntriesPerUser,
        uint256 maxFreeEntriesPerUser
    ) internal {
        lotteryRounds[dayId] = LotteryRound({
            dayId: dayId,
            seasonId: seasonId,
            entryPrice: entryPrice,
            maxEntriesPerUser: maxEntriesPerUser,
            maxFreeEntriesPerUser: maxFreeEntriesPerUser,
            totalEntries: 0,
            totalPaid: 0,
            winner: address(0),
            finalized: false,
            prizeType: PrizeType.FP, // Default, will be set when winner is drawn
            prizeTokenAddress: address(0),
            prizeSeasonId: 0,
            prizeAmount: 0
        });

        emit LotteryRoundCreated(dayId, seasonId, entryPrice, maxEntriesPerUser, maxFreeEntriesPerUser);
    }

    /**
     * @notice Ensure a lottery round exists for a specific day, creating it with defaults if needed
     * @param dayId Day identifier for the round
     * @param round Storage reference to the lottery round
     * @dev Auto-creates round with default values if it doesn't exist yet
     */
    function _ensureRoundExists(uint256 dayId, LotteryRound storage round) internal {
        // If round doesn't exist, create it with defaults
        if (round.dayId != dayId) {
            _createRound(
                dayId, defaultSeasonId, defaultEntryPrice, defaultMaxEntriesPerUser, defaultMaxFreeEntriesPerUser
            );
        }
    }

    /**
     * @notice Draw winner for a specific lottery round with off-chain randomness
     * @param dayId Day identifier for the lottery round
     * @param winningIndex Index of the winning entry (generated off-chain)
     * @param prize Prize data (type, token address for ERC20, season ID for FP, and amount)
     * @dev The admin generates a random number off-chain and passes the winning index.
     *      The prize is transferred from the admin to the contract, then from the contract to the winner.
     *      For ERC20 prizes, any ERC20 token can be used (USDT, USDC, POL, etc.).
     *      For FP prizes, the seasonId is independent of the seasonId used for burning entry fees.
     */
    function drawWinner(uint256 dayId, uint256 winningIndex, PrizeData calldata prize)
        external
        onlyRole(LOTTERY_ADMIN_ROLE)
        nonReentrant
    {
        // Early validation of prize data (before storage access)
        require(prize.amount > 0, "Invalid prize amount");
        // If prize is ERC20, token address must be valid (not zero)
        if (prize.prizeType == PrizeType.ERC20) {
            require(prize.tokenAddress != address(0), "Invalid token address for ERC20");
        }

        LotteryRound storage round = lotteryRounds[dayId];

        require(round.dayId == dayId, "Lottery not active");
        require(!round.finalized, "Already finalized");
        require(round.totalEntries > 0, "No entries");
        require(winningIndex < round.totalEntries, "Invalid winning index");

        // Get winner from entries array using the provided index
        address winner = entries[dayId][winningIndex];

        // Validate winner address
        require(winner != address(0), "Invalid winner address");

        // Transfer prize from admin to contract, then from contract to winner
        if (prize.prizeType == PrizeType.FP) {
            // Transfer FP tokens from admin to contract
            fpToken.agentTransferFrom(msg.sender, address(this), prize.seasonId, prize.amount, "");
            // Transfer FP tokens from contract to winner
            fpToken.agentTransferFrom(address(this), winner, prize.seasonId, prize.amount, "");
        } else {
            IERC20(prize.tokenAddress).safeTransferFrom(msg.sender, winner, prize.amount);
        }

        // Update state only after successful transfer (Effects after Interactions in this case)
        round.winner = winner;
        round.finalized = true;
        round.prizeType = prize.prizeType;
        round.prizeTokenAddress = prize.tokenAddress;
        round.prizeSeasonId = prize.seasonId;
        round.prizeAmount = prize.amount;

        emit WinnerDrawn(dayId, winner, prize.prizeType, prize.tokenAddress, prize.seasonId, prize.amount);
    }

    // ============ User Functions ============

    /**
     * @notice Claim free entry for today's lottery using a server signature
     * @param signature EIP-712 signature from an address with FREE_ENTRY_SIGNER_ROLE
     * @dev User must have a valid signature from the backend server authorizing entry for today.
     *      Users can claim multiple free entries if the backend provides multiple signatures.
     *      The signature is specific to the dayId and nonce, preventing reuse.
     *      The nonce is per-round (per-day), resetting for each new day.
     *      The user pays gas for their own entry.
     */
    function claimFreeEntry(bytes calldata signature) external nonReentrant whenNotPaused {
        uint256 dayId = getCurrentDayId();
        LotteryRound storage round = lotteryRounds[dayId];

        // Ensure round exists (auto-create if needed)
        _ensureRoundExists(dayId, round);

        // Check lottery is active
        require(!round.finalized, "Lottery not active");

        // Check that claiming free entry won't exceed maximum total entries
        uint256 currentUserEntries = userEntries[dayId][msg.sender];
        require(currentUserEntries < round.maxEntriesPerUser, "Max entries exceeded");

        // Get current nonce for this user in this round
        uint256 nonce = nonces[dayId][msg.sender];

        // Check that claiming free entry won't exceed maximum free entries
        // (nonce represents the number of free entries already claimed)
        require(nonce < round.maxFreeEntriesPerUser, "Max free entries exceeded");

        // Verify signature for this specific day and nonce
        bytes32 structHash = keccak256(abi.encode(FREE_ENTRY_TYPEHASH, msg.sender, dayId, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        // Validate signer is not zero address (invalid signature)
        require(signer != address(0), "Invalid signature");
        require(hasRole(FREE_ENTRY_SIGNER_ROLE, signer), "Invalid signer");

        // Increment nonce for this round before effects to prevent reentrancy
        nonces[dayId][msg.sender] = nonce + 1;

        // Grant free entry (use cached value)
        userEntries[dayId][msg.sender] = currentUserEntries + 1;
        entries[dayId].push(msg.sender);
        round.totalEntries++;

        emit FreeEntryGranted(msg.sender, dayId, nonce);
    }

    /**
     * @notice Purchase a lottery entry using FP tokens
     * @dev Can be called multiple times per day until reaching the round's maxEntriesPerUser
     * @dev Each transaction purchases exactly 1 entry
     */
    function buyEntry() external nonReentrant whenNotPaused {
        uint256 dayId = getCurrentDayId();
        LotteryRound storage round = lotteryRounds[dayId];

        // Ensure round exists (auto-create if needed)
        _ensureRoundExists(dayId, round);

        // Check lottery is active
        require(!round.finalized, "Lottery not active");

        // Check current entries
        uint256 currentEntries = userEntries[dayId][msg.sender];

        // Check total entries won't exceed maximum
        require(currentEntries < round.maxEntriesPerUser, "Max entries exceeded");

        // Transfer FP tokens from user to contract using agentTransferFrom (requires TRANSFER_AGENT_ROLE)
        fpToken.agentTransferFrom(msg.sender, address(this), round.seasonId, round.entryPrice, "");

        // Burn the received FP tokens
        fpToken.burn(address(this), round.seasonId, round.entryPrice);

        // Add 1 entry
        userEntries[dayId][msg.sender] = currentEntries + 1;
        entries[dayId].push(msg.sender);
        round.totalEntries++;
        round.totalPaid += round.entryPrice; // Track total FP tokens paid for this round

        emit EntryPurchased(msg.sender, dayId, 1);
    }

    // ============ View Functions ============

    /**
     * @notice Get lottery round information for a specific day
     * @param dayId Day identifier
     * @return Lottery round data
     */
    function getLotteryRound(uint256 dayId) external view returns (LotteryRound memory) {
        return lotteryRounds[dayId];
    }

    /**
     * @notice Get user's entry count for a specific day
     * @param dayId Day identifier
     * @param user User address
     * @return Number of entries
     */
    function getUserEntries(uint256 dayId, address user) external view returns (uint256) {
        return userEntries[dayId][user];
    }

    /**
     * @notice Get user's nonce (free entries claimed) for a specific day
     * @param dayId Day identifier
     * @param user User address
     * @return Number of free entries claimed (nonce value)
     */
    function getUserNonce(uint256 dayId, address user) external view returns (uint256) {
        return nonces[dayId][user];
    }

    /**
     * @notice Get entry address at a specific index for a given day
     * @param dayId Day identifier
     * @param index Index of the entry
     * @return Address of the user at the specified index
     */
    function getEntry(uint256 dayId, uint256 index) external view returns (address) {
        require(index < entries[dayId].length, "Index out of bounds");
        return entries[dayId][index];
    }

    /**
     * @notice Get total entries for a specific day
     * @param dayId Day identifier
     * @return Total number of entries
     */
    function getTotalEntries(uint256 dayId) external view returns (uint256) {
        return lotteryRounds[dayId].totalEntries;
    }

    /**
     * @notice Get current day ID
     * @return Current day identifier (timestamp / 1 day)
     */
    function getCurrentDayId() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /**
     * @notice Get remaining entries available for a user on a specific day
     * @param dayId Day identifier
     * @param user User address
     * @return remainingFreeEntries Number of free entries the user can still claim
     * @return remainingTotalEntries Total number of entries (free + paid) the user can still claim/buy
     */
    function getRemainingEntries(uint256 dayId, address user)
        external
        view
        returns (uint256 remainingFreeEntries, uint256 remainingTotalEntries)
    {
        LotteryRound storage round = lotteryRounds[dayId];

        // If round doesn't exist, use default values
        uint256 maxFree = (round.dayId == dayId) ? round.maxFreeEntriesPerUser : defaultMaxFreeEntriesPerUser;
        uint256 maxTotal = (round.dayId == dayId) ? round.maxEntriesPerUser : defaultMaxEntriesPerUser;

        // Get user's current entries
        uint256 currentFreeEntries = nonces[dayId][user];
        uint256 currentTotalEntries = userEntries[dayId][user];

        // Calculate remaining entries
        remainingFreeEntries = maxFree > currentFreeEntries ? maxFree - currentFreeEntries : 0;
        remainingTotalEntries = maxTotal > currentTotalEntries ? maxTotal - currentTotalEntries : 0;

        return (remainingFreeEntries, remainingTotalEntries);
    }

    /**
     * @notice Get EIP-712 domain separator for client-side signing
     * @return Domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ============ ERC1155Receiver Implementation ============

    /**
     * @notice Handles the receipt of a single ERC1155 token type
     * @return bytes4 magic value to confirm the transfer
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @notice Handles the receipt of multiple ERC1155 token types
     * @return bytes4 magic value to confirm the transfer
     */
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
