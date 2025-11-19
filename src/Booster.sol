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
        OPEN, // 0 - Accepting boosts
        CLOSED, // 1 - No more boosts, fight ongoing
        RESOLVED // 2 - Fight ended, results submitted
    }

    enum WinMethod {
        KNOCKOUT, // 0 - KO/TKO
        SUBMISSION, // 1 - Submission
        DECISION, // 2 - Decision
        NO_CONTEST // 3 - No-Contest
    }

    enum Corner {
        RED, // 0
        BLUE, // 1
        NONE // 2 - No winner (e.g., no-contest)
    }

    struct Fight {
        FightStatus status;
        Corner winner;
        WinMethod method;
        uint256 bonusPool; // Manager-deposited bonus FP
        uint256 originalPool; // Total user boost stakes
        uint256 sumWinnersStakes; // Sum of all winning users' stakes
        uint256 winningPoolTotalShares; // Total shares (sum of points * stakes for all winners)
        uint256 pointsForWinner; // Points if you picked correct winner only
        uint256 pointsForWinnerMethod; // Points if you picked correct winner AND method
        uint256 claimedAmount; // Amount claimed from the pool so far
        uint256 boostCutoff; // Unix timestamp after which boosts are rejected (0 = uses status only)
        bool cancelled; // Fight cancelled/no-contest - full refund of principal
    }

    struct Event {
        uint256 seasonId; // Which FP season this event uses
        uint256 numFights; // Number of fights in the event (fights are 1, 2, 3, ..., numFights)
        bool exists;
        uint256 claimDeadline; // unix timestamp after which claims are rejected (0 = no limit)
    }

    struct Boost {
        address user;
        uint256 amount; // FP staked (can be increased)
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

    struct ClaimInput {
        uint256 fightId;
        uint256[] boostIndices;
    }

    // ============ Storage ============
    FP1155 public immutable FP;

    // Minimum boost amount per boost (can be 0 to disable)
    uint256 public minBoostAmount;

    // eventId => Event
    mapping(string => Event) private events;

    // eventId => fightId => Fight
    mapping(string => mapping(uint256 => Fight)) private fights;

    // eventId => fightId => array of Boosts
    mapping(string => mapping(uint256 => Boost[])) private boosts;

    // eventId => fightId => user => boost indices
    mapping(string => mapping(uint256 => mapping(address => uint256[]))) private userBoostIndices;

    // ============ Events ============
    event EventCreated(string indexed eventId, uint256 numFights, uint256 indexed seasonId);
    event EventClaimDeadlineUpdated(string indexed eventId, uint256 deadline);
    event FightStatusUpdated(string indexed eventId, uint256 indexed fightId, FightStatus status);
    event FightBoostCutoffUpdated(string indexed eventId, uint256 indexed fightId, uint256 cutoff);
    event FightCancelled(string indexed eventId, uint256 indexed fightId);
    event MinBoostAmountUpdated(uint256 oldAmount, uint256 newAmount);
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
        Corner indexed winner,
        WinMethod method,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod,
        uint256 sumWinnersStakes,
        uint256 winningPoolTotalShares
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
    event FightPurged(string indexed eventId, uint256 indexed fightId, uint256 unclaimedPool);

    // ============ Constructor ============
    constructor(address _fp, address admin) {
        require(_fp != address(0), "fp=0");
        require(admin != address(0), "admin=0");

        FP = FP1155(_fp);
        minBoostAmount = 0; // Default: no minimum
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set minimum boost amount (0 to disable)
     * @param newMin New minimum boost amount in FP wei
     */
    function setMinBoostAmount(uint256 newMin) external onlyRole(OPERATOR_ROLE) {
        uint256 oldMin = minBoostAmount;
        minBoostAmount = newMin;
        emit MinBoostAmountUpdated(oldMin, newMin);
    }

    /**
     * @notice Create a new event with multiple fights
     * @param eventId Unique identifier for the event (e.g., "UFC_300")
     * @param numFights Number of fights in the event (fights are 1, 2, 3, ..., numFights)
     * @param seasonId Which FP season this event uses
     */
    function createEvent(string calldata eventId, uint256 numFights, uint256 seasonId)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(!events[eventId].exists, "event exists");
        require(numFights > 0, "no fights");

        // Verify season is valid and open
        require(FP.seasonStatus(seasonId) == FP1155.SeasonStatus.OPEN, "season not open");

        // Create event
        events[eventId] = Event({seasonId: seasonId, numFights: numFights, exists: true, claimDeadline: 0});

        // Initialize all fights as OPEN (fightIds are 1, 2, 3, ..., numFights)
        for (uint256 i = 1; i <= numFights; i++) {
            fights[eventId][i].status = FightStatus.OPEN;
        }

        emit EventCreated(eventId, numFights, seasonId);
    }

    /**
     * @notice Update fight status (optional, mainly for manual control)
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param newStatus New status (can only move forward)
     */
    function updateFightStatus(string calldata eventId, uint256 fightId, FightStatus newStatus)
        external
        onlyRole(OPERATOR_ROLE)
    {
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

    /**
     * @notice Set boost cutoff time for a fight (after which new boosts are rejected)
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param cutoff Unix timestamp (0 = rely on status only)
     */
    function setFightBoostCutoff(string calldata eventId, uint256 fightId, uint256 cutoff)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(events[eventId].exists, "event not exists");
        Fight storage fight = fights[eventId][fightId];
        require(fight.status != FightStatus.RESOLVED, "fight resolved");

        fight.boostCutoff = cutoff;
        emit FightBoostCutoffUpdated(eventId, fightId, cutoff);
    }

    /**
     * @notice Set boost cutoff time for all fights in an event
     * @param eventId Event identifier
     * @param cutoff Unix timestamp (0 = rely on status only)
     */
    function setEventBoostCutoff(string calldata eventId, uint256 cutoff) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");

        Event storage evt = events[eventId];
        // Iterate through all fights (fightIds are 1, 2, 3, ..., numFights)
        for (uint256 i = 1; i <= evt.numFights; i++) {
            Fight storage fight = fights[eventId][i];
            // Only set cutoff for fights that are not resolved
            if (fight.status != FightStatus.RESOLVED) {
                fight.boostCutoff = cutoff;
                emit FightBoostCutoffUpdated(eventId, i, cutoff);
            }
        }
    }

    /**
     * @notice Cancel a fight and enable full refunds (no-contest scenario)
     * @param eventId Event identifier
     * @param fightId Fight number
     */
    function cancelFight(string calldata eventId, uint256 fightId) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");
        Fight storage fight = fights[eventId][fightId];
        require(fight.status != FightStatus.RESOLVED, "fight already resolved");

        fight.status = FightStatus.RESOLVED;
        fight.cancelled = true;
        fight.winner = Corner.NONE;
        fight.method = WinMethod.NO_CONTEST;

        emit FightCancelled(eventId, fightId);
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
        // Iterate through all fights (fightIds are 1, 2, 3, ..., numFights)
        for (uint256 i = 1; i <= evt.numFights; i++) {
            Fight storage fight = fights[eventId][i];
            if (fight.status == FightStatus.RESOLVED) {
                uint256 poolAmount = fight.originalPool + fight.bonusPool;
                if (poolAmount == 0) continue;

                uint256 unclaimedPool = poolAmount - fight.claimedAmount;

                if (unclaimedPool > 0) {
                    emit FightPurged(eventId, i, unclaimedPool);
                    totalSweep += unclaimedPool;
                    fight.claimedAmount = poolAmount;
                }
            }
        }

        if (totalSweep > 0) {
            FP.safeTransferFrom(address(this), recipient, evt.seasonId, totalSweep, "");
        }
        emit EventPurged(eventId, recipient, totalSweep);
    }

    // ============ Manager Functions ============

    /**
     * @notice Manager deposits FP bonus to a fight's prize pool
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param amount Amount of FP to deposit as bonus
     */
    function depositBonus(string calldata eventId, uint256 fightId, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
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
     * @param sumWinnersStakes Sum of all winning users' stakes
     * @param winningPoolTotalShares Total shares (sum of points * stakes for all winners)
     */
    function submitFightResult(
        string calldata eventId,
        uint256 fightId,
        Corner winner,
        WinMethod method,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod,
        uint256 sumWinnersStakes,
        uint256 winningPoolTotalShares
    ) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");

        // Validate points parameters
        require(pointsForWinner > 0, "points for winner must be > 0");
        require(pointsForWinnerMethod >= pointsForWinner, "method points must be >= winner points");

        // Validate winner/method consistency
        if (winner == Corner.NONE) {
            require(method == WinMethod.NO_CONTEST, "NONE winner requires NO_CONTEST method");
        }

        Fight storage fight = fights[eventId][fightId];
        require(fight.status != FightStatus.RESOLVED, "already resolved");
        require(!fight.cancelled, "fight cancelled");

        // Store result
        fight.status = FightStatus.RESOLVED;
        fight.winner = winner;
        fight.method = method;
        fight.pointsForWinner = pointsForWinner;
        fight.pointsForWinnerMethod = pointsForWinnerMethod;
        fight.sumWinnersStakes = sumWinnersStakes;
        fight.winningPoolTotalShares = winningPoolTotalShares;

        emit FightResultSubmitted(
            eventId,
            fightId,
            winner,
            method,
            pointsForWinner,
            pointsForWinnerMethod,
            sumWinnersStakes,
            winningPoolTotalShares
        );
    }

    // ============ User Functions ============

    /**
     * @notice Place new boosts on fights
     * @param eventId Event identifier
     * @param inputs Array of boost inputs
     */
    function placeBoosts(string calldata eventId, BoostInput[] calldata inputs) external nonReentrant {
        require(events[eventId].exists, "event not exists");
        require(inputs.length > 0, "no boosts");

        Event storage evt = events[eventId];
        uint256 seasonId = evt.seasonId;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < inputs.length; i++) {
            BoostInput calldata input = inputs[i];
            require(input.amount > 0, "amount=0");
            require(input.amount >= minBoostAmount, "below min boost");

            // Validate that fightId exists in the event (O(1) range check: fights are 1, 2, 3, ..., numFights)
            require(input.fightId >= 1 && input.fightId <= evt.numFights, "fightId not in event");

            Fight storage fight = fights[eventId][input.fightId];
            require(fight.status == FightStatus.OPEN, "fight not open");
            require(!fight.cancelled, "fight cancelled");

            // Check boost cutoff if set
            if (fight.boostCutoff > 0) {
                require(block.timestamp < fight.boostCutoff, "boost cutoff passed");
            }

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
    function addToBoost(string calldata eventId, uint256 fightId, uint256 boostIndex, uint256 additionalAmount)
        external
        nonReentrant
    {
        require(events[eventId].exists, "event not exists");
        require(additionalAmount > 0, "amount=0");
        require(additionalAmount >= minBoostAmount, "below min boost");

        Event storage evt = events[eventId];
        require(fightId >= 1 && fightId <= evt.numFights, "fightId not in event");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.OPEN, "fight not open");
        require(!fight.cancelled, "fight cancelled");

        // Check boost cutoff if set
        if (fight.boostCutoff > 0) {
            require(block.timestamp < fight.boostCutoff, "boost cutoff passed");
        }

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
    function claimReward(string calldata eventId, uint256 fightId, uint256[] calldata boostIndices)
        external
        nonReentrant
    {
        require(events[eventId].exists, "event not exists");

        Event storage evt = events[eventId];
        require(fightId >= 1 && fightId <= evt.numFights, "fightId not in event");

        uint256 deadline = evt.claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.RESOLVED, "not resolved");

        uint256 seasonId = evt.seasonId;
        Boost[] storage fightBoosts = boosts[eventId][fightId];

        // Handle cancelled fight (full refund of principal)
        if (fight.cancelled) {
            uint256 refund = _processCancelledBoostRefund(fightBoosts, boostIndices, msg.sender);

            require(refund > 0, "nothing to refund");
            
            // Update claimed amount to reflect refunds paid
            fight.claimedAmount += refund;
            
            FP.safeTransferFrom(address(this), msg.sender, seasonId, refund, "");
            return;
        }

        // Normal claim flow (winning boosts)
        // If no winners, no one can claim rewards (check early to avoid unnecessary computation)
        require(fight.sumWinnersStakes > 0 && fight.winningPoolTotalShares > 0, "no winners");
        uint256 totalPayout = 0;

        uint256 prizePool = fight.originalPool - fight.sumWinnersStakes + fight.bonusPool;

        for (uint256 i = 0; i < boostIndices.length; i++) {
            totalPayout += _processWinningBoostClaim(
                eventId, fightId, fight, fightBoosts, boostIndices[i], msg.sender, prizePool
            );
        }

        // Transfer total payout to user
        if (totalPayout > 0) {
            FP.safeTransferFrom(address(this), msg.sender, seasonId, totalPayout, "");
        }
    }

    /**
     * @notice Claim rewards for winning boosts across multiple fights in a single transaction
     * @param eventId Event identifier
     * @param inputs Array of claim inputs, each containing a fightId and boost indices
     */
    function claimRewards(string calldata eventId, ClaimInput[] calldata inputs) external nonReentrant {
        require(events[eventId].exists, "event not exists");
        require(inputs.length > 0, "no claims");

        Event storage evt = events[eventId];
        uint256 deadline = evt.claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");

        uint256 seasonId = evt.seasonId;
        uint256 totalPayout = 0;

        for (uint256 j = 0; j < inputs.length; j++) {
            ClaimInput calldata input = inputs[j];
            require(input.fightId >= 1 && input.fightId <= evt.numFights, "fightId not in event");
            require(input.boostIndices.length > 0, "no boost indices");

            Fight storage fight = fights[eventId][input.fightId];
            require(fight.status == FightStatus.RESOLVED, "not resolved");

            Boost[] storage fightBoosts = boosts[eventId][input.fightId];

            // Handle cancelled fight (full refund of principal)
            if (fight.cancelled) {
                uint256 refund = _processCancelledBoostRefund(fightBoosts, input.boostIndices, msg.sender);

                if (refund > 0) {
                    // Update claimed amount to reflect refunds paid
                    fight.claimedAmount += refund;
                    totalPayout += refund;
                }
                continue;
            }

            // Normal claim flow (winning boosts)
            // If no winners, skip this fight
            if (fight.sumWinnersStakes == 0 || fight.winningPoolTotalShares == 0) {
                continue;
            }

            uint256 prizePool = fight.originalPool - fight.sumWinnersStakes + fight.bonusPool;

            for (uint256 i = 0; i < input.boostIndices.length; i++) {
                totalPayout += _processWinningBoostClaim(
                    eventId, input.fightId, fight, fightBoosts, input.boostIndices[i], msg.sender, prizePool
                );
            }
        }

        // Transfer total payout to user
        require(totalPayout > 0, "nothing to claim");
        FP.safeTransferFrom(address(this), msg.sender, seasonId, totalPayout, "");
    }

    // ============ View Functions ============

    /**
     * @notice Get event details
     * @param eventId Event identifier
     * @return seasonId The FP season for this event
     * @return numFights Number of fights in the event (fights are 1, 2, 3, ..., numFights)
     * @return exists Whether the event exists
     */
    function getEvent(string calldata eventId)
        external
        view
        returns (uint256 seasonId, uint256 numFights, bool exists)
    {
        Event storage evt = events[eventId];
        return (evt.seasonId, evt.numFights, evt.exists);
    }

    /**
     * @notice Get the claim deadline for an event
     */
    function getEventClaimDeadline(string calldata eventId) external view returns (uint256) {
        return events[eventId].claimDeadline;
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
     * @return sumWinnersStakes Sum of all winning users' stakes
     * @return winningPoolTotalShares Total shares (sum of points * stakes for all winners)
     * @return pointsForWinner Points for correct winner
     * @return pointsForWinnerMethod Points for correct winner+method
     * @return claimedAmount Amount claimed from the pool so far
     * @return boostCutoff Boost cutoff timestamp
     * @return cancelled Whether fight is cancelled (refund mode)
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
            uint256 sumWinnersStakes,
            uint256 winningPoolTotalShares,
            uint256 pointsForWinner,
            uint256 pointsForWinnerMethod,
            uint256 claimedAmount,
            uint256 boostCutoff,
            bool cancelled
        )
    {
        Fight storage fight = fights[eventId][fightId];
        return (
            fight.status,
            fight.winner,
            fight.method,
            fight.bonusPool,
            fight.originalPool,
            fight.sumWinnersStakes,
            fight.winningPoolTotalShares,
            fight.pointsForWinner,
            fight.pointsForWinnerMethod,
            fight.claimedAmount,
            fight.boostCutoff,
            fight.cancelled
        );
    }

    /**
     * @notice Get total prize pool for a fight (original + bonus)
     * @param eventId Event identifier
     * @param fightId Fight number
     * @return Total pool amount
     */
    function totalPool(string calldata eventId, uint256 fightId) external view returns (uint256) {
        Fight storage fight = fights[eventId][fightId];
        return fight.originalPool + fight.bonusPool;
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
    function quoteClaimable(string calldata eventId, uint256 fightId, address user, bool enforceDeadline)
        external
        view
        returns (uint256 totalClaimable)
    {
        Event storage evt = events[eventId];
        require(evt.exists, "event not exists");
        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.RESOLVED, "not resolved");

        if (enforceDeadline) {
            uint256 deadline = evt.claimDeadline;
            require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");
        }
        totalClaimable = 0;
        // If no winners, return zeros
        if (fight.sumWinnersStakes == 0 || fight.winningPoolTotalShares == 0) {
            return totalClaimable;
        }

        uint256[] storage indices = userBoostIndices[eventId][fightId][user];
        uint256 prizePool = fight.originalPool - fight.sumWinnersStakes + fight.bonusPool;
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
            // Calculate winnings from the pool based on points and stakes
            // Formula: (points * boost.amount * prizePool) / winningPoolTotalShares
            uint256 userShares = points * boost.amount;
            uint256 userWinnings = (prizePool * userShares) / fight.winningPoolTotalShares;
            uint256 payout = boost.amount + userWinnings;
            totalClaimable += payout;
        }
        return totalClaimable;
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

    // ============ Internal Helper Functions ============

    /**
     * @notice Process refund for cancelled fight boosts
     * @param fightBoosts Array of boosts for the fight
     * @param boostIndices Array of boost indices to refund
     * @param user Address claiming the refund
     * @return refund Total refund amount
     */
    function _processCancelledBoostRefund(Boost[] storage fightBoosts, uint256[] calldata boostIndices, address user)
        internal
        returns (uint256 refund)
    {
        refund = 0;
        for (uint256 i = 0; i < boostIndices.length; i++) {
            uint256 index = boostIndices[i];
            require(index < fightBoosts.length, "invalid boost index");

            Boost storage boost = fightBoosts[index];
            require(boost.user == user, "not boost owner");
            require(!boost.claimed, "already claimed");

            refund += boost.amount;
            boost.claimed = true;
        }
    }

    /**
     * @notice Process claim for a winning boost
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param fight Fight storage reference
     * @param fightBoosts Array of boosts for the fight
     * @param boostIndex Index of the boost to claim
     * @param user Address claiming the reward
     * @param prizePool Prize pool (original + bonus) for the fight
     * @return payout Payout amount for this boost
     */
    function _processWinningBoostClaim(
        string calldata eventId,
        uint256 fightId,
        Fight storage fight,
        Boost[] storage fightBoosts,
        uint256 boostIndex,
        address user,
        uint256 prizePool
    ) internal returns (uint256 payout) {
        require(boostIndex < fightBoosts.length, "invalid boost index");

        Boost storage boost = fightBoosts[boostIndex];
        require(boost.user == user, "not boost owner");
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

        // Calculate winnings from the pool based on points and stakes
        // Formula: (points * boost.amount * prizePool) / winningPoolTotalShares
        uint256 userShares = points * boost.amount;
        uint256 winnings = (prizePool * userShares) / fight.winningPoolTotalShares;
        payout = winnings + boost.amount;

        boost.claimed = true;

        fight.claimedAmount += payout;

        emit RewardClaimed(eventId, fightId, user, boostIndex, payout, points);
    }

    // ============ Interface Support ============
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
