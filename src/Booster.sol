// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC1155Holder} from "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {FP1155} from "./FP1155.sol";

/**
 * @title Booster
 * @notice UFC Strike Now pick'em booster contract
 * @dev Users boost their fight predictions with FP tokens. Winners split the prize pool proportionally.
 *      Requires TRANSFER_AGENT_ROLE on the FP1155 contract.
 */
contract Booster is AccessControl, ReentrancyGuard, ERC1155Holder {
    // ============ Roles ============
    // Single privileged role controlling all admin, management and result operations
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Types ============
    enum FightStatus {
        OPEN,     // 0 - Accepting boosts
        CLOSED,   // 1 - No more boosts, fight ongoing
        RESOLVED  // 2 - Fight ended, results submitted
    }

    enum WinMethod {
        KNOCKOUT,    // 0 - KO/TKO
        SUBMISSION,  // 1 - Submission
        DECISION,    // 2 - Decision
        NO_CONTEST   // 3 - No-Contest
    }

    enum Corner {
        RED,   // 0
        BLUE,  // 1
        NONE   // 2 - No winner (e.g., no-contest)
    }

    struct Fight {
        FightStatus status;
        Corner winner;
        WinMethod method;
        uint256 bonusPool;              // Manager-deposited bonus FP
        uint256 originalPool;           // Total user boost stakes
        uint256 totalWinningPoints;     // Submitted by server after offchain calculation
        uint256 pointsForWinner;        // Points if you picked correct winner only
        uint256 pointsForWinnerMethod;  // Points if you picked correct winner AND method
        uint256 claimedOriginal;        // Track original pool claimed so far
        uint256 claimedBonus;           // Track bonus pool claimed so far
        bool calculationSubmitted;      // Server has submitted totalWinningPoints
    }

    struct Event {
        uint256 seasonId;        // Which FP season this event uses
        uint256[] fightIds;      // Fixed array of fight numbers
        bool exists;
        uint256 claimDeadline;   // unix timestamp after which claims are rejected (0 = no limit)
    }

    struct Boost {
        address user;
        uint256 amount;              // FP staked (can be increased)
        Corner predictedWinner;
        WinMethod predictedMethod;
        bool claimed;
    }

    struct BoostInput {
        uint256 fightId;
        uint256 amount;
        Corner predictedWinner;
        WinMethod predictedMethod;
    }

    // ============ Storage ============
    FP1155 public immutable FP;

    // eventId => Event
    mapping(string => Event) private events;

    // eventId => fightId => Fight
    mapping(string => mapping(uint256 => Fight)) private fights;

    // eventId => fightId => array of Boosts
    mapping(string => mapping(uint256 => Boost[])) private boosts;

    // eventId => fightId => user => boost indices
    mapping(string => mapping(uint256 => mapping(address => uint256[]))) private userBoostIndices;

    // ============ Events ============
    event EventCreated(string indexed eventId, uint256[] fightIds, uint256 seasonId);
    event EventClaimDeadlineUpdated(string indexed eventId, uint256 deadline);
    event FightStatusUpdated(string indexed eventId, uint256 indexed fightId, FightStatus status);
    event BonusDeposited(string indexed eventId, uint256 indexed fightId, address indexed manager, uint256 amount);
    event BoostPlaced(
        string indexed eventId,
        uint256 indexed fightId,
        address indexed user,
        uint256 boostIndex,
        uint256 amount,
        Corner winner,
        WinMethod method
    );
    event BoostIncreased(
        string indexed eventId,
        uint256 indexed fightId,
        address indexed user,
        uint256 boostIndex,
        uint256 additionalAmount,
        uint256 newTotal
    );
    event FightResultSubmitted(
        string indexed eventId,
        uint256 indexed fightId,
        Corner winner,
        WinMethod method,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod,
        uint256 totalWinningPoints
    );
    event RewardClaimed(
        string indexed eventId,
        uint256 indexed fightId,
        address indexed user,
        uint256 boostIndex,
        uint256 payout,
        uint256 points
    );
    event EventPurged(string indexed eventId, address indexed recipient, uint256 amount);
    event FightPurged(string indexed eventId, uint256 indexed fightId, uint256 unclaimedOriginal, uint256 unclaimedBonus);

    // ============ Constructor ============
    constructor(address _fp, address admin) {
        require(_fp != address(0), "fp=0");
        require(admin != address(0), "admin=0");
        
    FP = FP1155(_fp);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ============ Admin Functions ============

    /**
     * @notice Create a new event with multiple fights
     * @param eventId Unique identifier for the event (e.g., "UFC_300")
     * @param fightIds Array of fight numbers (immutable after creation)
     * @param seasonId Which FP season this event uses
     */
    function createEvent(
        string calldata eventId,
        uint256[] calldata fightIds,
        uint256 seasonId
    ) external onlyRole(OPERATOR_ROLE) {
        require(!events[eventId].exists, "event exists");
        require(fightIds.length > 0, "no fights");

        // Verify season is valid and open
    require(FP.seasonStatus(seasonId) == FP1155.SeasonStatus.OPEN, "season not open");

        // Create event
        events[eventId] = Event({
            seasonId: seasonId,
            fightIds: fightIds,
            exists: true,
            claimDeadline: 0
        });

        // Initialize all fights as OPEN
        for (uint256 i = 0; i < fightIds.length; i++) {
            fights[eventId][fightIds[i]].status = FightStatus.OPEN;
        }

        emit EventCreated(eventId, fightIds, seasonId);
    }

    /**
     * @notice Update fight status (optional, mainly for manual control)
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param newStatus New status (can only move forward)
     */
    function updateFightStatus(
        string calldata eventId,
        uint256 fightId,
        FightStatus newStatus
    ) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");
        
        Fight storage fight = fights[eventId][fightId];
        FightStatus currentStatus = fight.status;

        // Cannot modify after resolved
        require(currentStatus != FightStatus.RESOLVED, "fight already resolved");

        // Status can only move forward
        require(uint256(newStatus) >= uint256(currentStatus), "invalid status transition");

        fight.status = newStatus;
        emit FightStatusUpdated(eventId, fightId, newStatus);
    }

    // ============ Manager Functions ============

    /**
     * @notice Manager deposits FP bonus to a fight's prize pool
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param amount Amount of FP to deposit as bonus
     */
    function depositBonus(
        string calldata eventId,
        uint256 fightId,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        require(events[eventId].exists, "event not exists");
        require(amount > 0, "amount=0");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status != FightStatus.RESOLVED, "fight resolved");

        uint256 seasonId = events[eventId].seasonId;

        // Pull FP from manager
    FP.agentTransferFrom(msg.sender, address(this), seasonId, amount, "");

        fight.bonusPool += amount;
        emit BonusDeposited(eventId, fightId, msg.sender, amount);
    }

    // ============ Operator Functions ============

    /**
     * @notice Server submits fight result and total winning points
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param winner Which corner won
     * @param method How they won
     * @param pointsForWinner Points awarded for correct winner only
     * @param pointsForWinnerMethod Points awarded for correct winner AND method
     * @param totalWinningPoints Sum of all winning users' points (calculated offchain)
     */
    function submitFightResult(
        string calldata eventId,
        uint256 fightId,
        Corner winner,
        WinMethod method,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod,
        uint256 totalWinningPoints
    ) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");
        require(totalWinningPoints > 0, "no winners");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status != FightStatus.RESOLVED, "already resolved");

        // Store result
        fight.status = FightStatus.RESOLVED;
        fight.winner = winner;
        fight.method = method;
        fight.pointsForWinner = pointsForWinner;
        fight.pointsForWinnerMethod = pointsForWinnerMethod;
        fight.totalWinningPoints = totalWinningPoints;
        fight.calculationSubmitted = true;

        emit FightResultSubmitted(
            eventId,
            fightId,
            winner,
            method,
            pointsForWinner,
            pointsForWinnerMethod,
            totalWinningPoints
        );
    }

    // ============ User Functions ============

    /**
     * @notice Place new boosts on fights
     * @param eventId Event identifier
     * @param inputs Array of boost inputs
     */
    function placeBoosts(
        string calldata eventId,
        BoostInput[] calldata inputs
    ) external nonReentrant {
        require(events[eventId].exists, "event not exists");
        // If a deadline is set and passed, no new boosts should be allowed (conservative)
        uint256 deadline = events[eventId].claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");
        require(inputs.length > 0, "no boosts");

    uint256 seasonId = events[eventId].seasonId;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < inputs.length; i++) {
            BoostInput calldata input = inputs[i];
            require(input.amount > 0, "amount=0");

            Fight storage fight = fights[eventId][input.fightId];
            require(fight.status == FightStatus.OPEN, "fight not open");

            // Create boost
            Boost memory newBoost = Boost({
                user: msg.sender,
                amount: input.amount,
                predictedWinner: input.predictedWinner,
                predictedMethod: input.predictedMethod,
                claimed: false
            });

            uint256 boostIndex = boosts[eventId][input.fightId].length;
            boosts[eventId][input.fightId].push(newBoost);
            userBoostIndices[eventId][input.fightId][msg.sender].push(boostIndex);

            fight.originalPool += input.amount;
            totalAmount += input.amount;

            emit BoostPlaced(
                eventId,
                input.fightId,
                msg.sender,
                boostIndex,
                input.amount,
                input.predictedWinner,
                input.predictedMethod
            );
        }

        // Pull total FP from user
    FP.agentTransferFrom(msg.sender, address(this), seasonId, totalAmount, "");
    }

    /**
     * @notice Add more FP to an existing boost
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param boostIndex Index of the boost to increase
     * @param additionalAmount Amount of FP to add
     */
    function addToBoost(
        string calldata eventId,
        uint256 fightId,
        uint256 boostIndex,
        uint256 additionalAmount
    ) external nonReentrant {
        require(events[eventId].exists, "event not exists");
        uint256 deadline = events[eventId].claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");
        require(additionalAmount > 0, "amount=0");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.OPEN, "fight not open");

        Boost[] storage fightBoosts = boosts[eventId][fightId];
        require(boostIndex < fightBoosts.length, "invalid boost index");

        Boost storage boost = fightBoosts[boostIndex];
        require(boost.user == msg.sender, "not boost owner");

        uint256 seasonId = events[eventId].seasonId;

        // Pull FP from user
    FP.agentTransferFrom(msg.sender, address(this), seasonId, additionalAmount, "");

        // Update boost and pool
        boost.amount += additionalAmount;
        fight.originalPool += additionalAmount;

        emit BoostIncreased(eventId, fightId, msg.sender, boostIndex, additionalAmount, boost.amount);
    }

    /**
     * @notice Claim rewards for winning boosts
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param boostIndices Array of boost indices to claim
     */
    function claimReward(
        string calldata eventId,
        uint256 fightId,
        uint256[] calldata boostIndices
    ) external nonReentrant {
        require(events[eventId].exists, "event not exists");
        uint256 deadline = events[eventId].claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.RESOLVED, "not resolved");
        require(fight.calculationSubmitted, "calculation not submitted");

        uint256 seasonId = events[eventId].seasonId;
        uint256 totalPayout = 0;

        Boost[] storage fightBoosts = boosts[eventId][fightId];

        for (uint256 i = 0; i < boostIndices.length; i++) {
            uint256 index = boostIndices[i];
            require(index < fightBoosts.length, "invalid boost index");

            Boost storage boost = fightBoosts[index];
            require(boost.user == msg.sender, "not boost owner");
            require(!boost.claimed, "already claimed");

            // Calculate points for this boost
            uint256 points = calculateUserPoints(
                boost.predictedWinner,
                boost.predictedMethod,
                fight.winner,
                fight.method,
                fight.pointsForWinner,
                fight.pointsForWinnerMethod
            );

            require(points > 0, "boost did not win");

            // Calculate payout: (points / totalPoints) * totalPool
            uint256 totalPool = fight.originalPool + fight.bonusPool;
            uint256 payout = (points * totalPool) / fight.totalWinningPoints;

            boost.claimed = true;
            totalPayout += payout;

            // Track claimed amounts by pool type
            uint256 shareOfOriginal = (points * fight.originalPool) / fight.totalWinningPoints;
            uint256 shareOfBonus = (points * fight.bonusPool) / fight.totalWinningPoints;
            
            fight.claimedOriginal += shareOfOriginal;
            fight.claimedBonus += shareOfBonus;

            emit RewardClaimed(eventId, fightId, msg.sender, index, payout, points);
        }

        // Transfer total payout to user
        if (totalPayout > 0) {
            FP.safeTransferFrom(address(this), msg.sender, seasonId, totalPayout, "");
        }
    }

    // ============ View Functions ============

    /**
     * @notice Get event details
     * @param eventId Event identifier
     * @return seasonId The FP season for this event
     * @return fightIds Array of fight numbers
     * @return exists Whether the event exists
     */
    function getEvent(string calldata eventId)
        external
        view
        returns (uint256 seasonId, uint256[] memory fightIds, bool exists)
    {
        Event storage evt = events[eventId];
        return (evt.seasonId, evt.fightIds, evt.exists);
    }

    /**
     * @notice Get the claim deadline for an event
     */
    function getEventClaimDeadline(string calldata eventId) external view returns (uint256) {
        return events[eventId].claimDeadline;
    }

    /**
     * @notice Set or update the claim deadline for an event (0 disables deadline)
     * @dev Non-decreasing: if already set, new value must be >= current
     */
    function setEventClaimDeadline(string calldata eventId, uint256 deadline) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");
        uint256 current = events[eventId].claimDeadline;
        if (current != 0) {
            require(deadline == 0 || deadline >= current, "deadline decrease");
        }
        events[eventId].claimDeadline = deadline;
        emit EventClaimDeadlineUpdated(eventId, deadline);
    }

    /**
     * @notice Purge unclaimed funds for all resolved fights in an event after deadline
     * @param eventId Event identifier
     * @param recipient Address to receive swept unclaimed FP
     */
    function purgeEvent(string calldata eventId, address recipient) external onlyRole(OPERATOR_ROLE) nonReentrant {
        require(events[eventId].exists, "event not exists");
        require(recipient != address(0), "recipient=0");
        uint256 deadline = events[eventId].claimDeadline;
        require(deadline != 0 && block.timestamp > deadline, "deadline not passed");

        Event storage evt = events[eventId];
        uint256 totalSweep = 0;
        uint256[] storage fightIds = evt.fightIds;
        for (uint256 i = 0; i < fightIds.length; i++) {
            uint256 fid = fightIds[i];
            Fight storage fight = fights[eventId][fid];
            if (fight.status == FightStatus.RESOLVED) {
                uint256 unclaimedOriginal = fight.originalPool - fight.claimedOriginal;
                uint256 unclaimedBonus = fight.bonusPool - fight.claimedBonus;
                if (unclaimedOriginal > 0 || unclaimedBonus > 0) {
                    emit FightPurged(eventId, fid, unclaimedOriginal, unclaimedBonus);
                    totalSweep += unclaimedOriginal + unclaimedBonus;
                    fight.claimedOriginal = fight.originalPool;
                    fight.claimedBonus = fight.bonusPool;
                }
            }
        }

        if (totalSweep > 0) {
            FP.safeTransferFrom(address(this), recipient, evt.seasonId, totalSweep, "");
        }
        emit EventPurged(eventId, recipient, totalSweep);
    }

    /**
     * @notice Get fight details
     * @param eventId Event identifier
     * @param fightId Fight number
     * @return status Current fight status
     * @return winner Winning corner (if resolved)
     * @return method Win method (if resolved)
     * @return bonusPool Manager bonus pool
     * @return originalPool User stakes pool
     * @return totalWinningPoints Total winning points
     * @return pointsForWinner Points for correct winner
     * @return pointsForWinnerMethod Points for correct winner+method
     * @return claimedOriginal Original pool claimed so far
     * @return claimedBonus Bonus pool claimed so far
     * @return calculationSubmitted Whether calculation is submitted
     */
    function getFight(string calldata eventId, uint256 fightId)
        external
        view
        returns (
            FightStatus status,
            Corner winner,
            WinMethod method,
            uint256 bonusPool,
            uint256 originalPool,
            uint256 totalWinningPoints,
            uint256 pointsForWinner,
            uint256 pointsForWinnerMethod,
            uint256 claimedOriginal,
            uint256 claimedBonus,
            bool calculationSubmitted
        )
    {
        Fight storage fight = fights[eventId][fightId];
        return (
            fight.status,
            fight.winner,
            fight.method,
            fight.bonusPool,
            fight.originalPool,
            fight.totalWinningPoints,
            fight.pointsForWinner,
            fight.pointsForWinnerMethod,
            fight.claimedOriginal,
            fight.claimedBonus,
            fight.calculationSubmitted
        );
    }

    /**
     * @notice Get all boosts for a user on a specific fight
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param user User address
     * @return Array of user's boosts
     */
    function getUserBoosts(string calldata eventId, uint256 fightId, address user)
        external
        view
        returns (Boost[] memory)
    {
        uint256[] storage indices = userBoostIndices[eventId][fightId][user];
        Boost[] storage allBoosts = boosts[eventId][fightId];
        
        Boost[] memory userBoosts = new Boost[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            userBoosts[i] = allBoosts[indices[i]];
        }
        
        return userBoosts;
    }

    /**
     * @notice Quote total claimable payout across a set of boosts for a user without state changes.
     * @dev Returns (claimableAmount, claimableOriginalShare, claimableBonusShare)
     *      Only includes boosts that are unclaimed winners. Reverts if fight not resolved or calculation not submitted.
     *      Does NOT enforce deadline (caller may want to see potential even if deadline passed); pass enforceDeadline=true to include deadline check.
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param user User address
     * @param enforceDeadline Whether to revert if claim deadline passed
     */
    function quoteClaimable(
        string calldata eventId,
        uint256 fightId,
        address user,
        bool enforceDeadline
    ) external view returns (uint256 totalClaimable, uint256 originalShare, uint256 bonusShare) {
        Event storage evt = events[eventId];
        require(evt.exists, "event not exists");
        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.RESOLVED, "not resolved");
        require(fight.calculationSubmitted, "calculation not submitted");

        if (enforceDeadline) {
            uint256 deadline = evt.claimDeadline;
            require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");
        }

        uint256[] storage indices = userBoostIndices[eventId][fightId][user];
        uint256 totalPool = fight.originalPool + fight.bonusPool;
        for (uint256 i = 0; i < indices.length; i++) {
            Boost storage boost = boosts[eventId][fightId][indices[i]];
            if (boost.claimed) continue;
            if (boost.user != user) continue; // defensive
            uint256 points = calculateUserPoints(
                boost.predictedWinner,
                boost.predictedMethod,
                fight.winner,
                fight.method,
                fight.pointsForWinner,
                fight.pointsForWinnerMethod
            );
            if (points == 0) continue; // losing boost
            uint256 payout = (points * totalPool) / fight.totalWinningPoints;
            uint256 payOriginal = (points * fight.originalPool) / fight.totalWinningPoints;
            uint256 payBonus = (points * fight.bonusPool) / fight.totalWinningPoints;
            totalClaimable += payout;
            originalShare += payOriginal;
            bonusShare += payBonus;
        }
    }

    /**
     * @notice Get indices of a user's boosts in the fight's boost array
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param user User address
     * @return indices Array of indices referencing the fight-level boosts array
     */
    function getUserBoostIndices(string calldata eventId, uint256 fightId, address user)
        external
        view
        returns (uint256[] memory indices)
    {
        uint256[] storage stored = userBoostIndices[eventId][fightId][user];
        indices = new uint256[](stored.length);
        for (uint256 i = 0; i < stored.length; i++) {
            indices[i] = stored[i];
        }
    }

    /**
     * @notice Calculate points earned for a prediction
     * @param predictedWinner User's predicted winner
     * @param predictedMethod User's predicted method
     * @param actualWinner Actual winner
     * @param actualMethod Actual method
     * @param pointsForWinner Points for correct winner only
     * @param pointsForWinnerMethod Points for correct winner+method
     * @return points Points earned
     */
    function calculateUserPoints(
        Corner predictedWinner,
        WinMethod predictedMethod,
        Corner actualWinner,
        WinMethod actualMethod,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod
    ) public pure returns (uint256 points) {
        if (predictedWinner != actualWinner) {
            return 0;
        }

        if (predictedMethod == actualMethod) {
            return pointsForWinnerMethod;
        }

        return pointsForWinner;
    }

    // ============ Interface Support ============
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
