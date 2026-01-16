// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { FP1155 } from "./FP1155.sol";

/**
 * @title Booster
 * @notice UFC Strike Now pick'em booster contract
 * @dev Users boost their fight predictions with FP tokens. Winners split the prize pool proportionally.
 *      Requires TRANSFER_AGENT_ROLE on the FP1155 contract.
 */
contract Booster is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC1155Receiver
{
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
        bool claimReady; // Final approval state - when true, results cannot be updated and claims are enabled
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

    struct FightResultInput {
        uint256 fightId;
        Corner winner;
        WinMethod method;
        uint256 pointsForWinner;
        uint256 pointsForWinnerMethod;
        uint256 sumWinnersStakes;
        uint256 winningPoolTotalShares;
    }

    // ============ Storage ============
    FP1155 public FP;

    // Minimum boost amount per boost (can be 0 to disable)
    uint256 public minBoostAmount;

    // Maximum limits for operational safety
    uint256 public maxFightsPerEvent;
    uint256 public maxBonusDeposit;

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
    event EventClaimReady(string indexed eventId, bool claimReady);
    event FightStatusUpdated(string indexed eventId, uint256 indexed fightId, FightStatus status);
    event FightBoostCutoffUpdated(string indexed eventId, uint256 indexed fightId, uint256 cutoff);
    event FightCancelled(string indexed eventId, uint256 indexed fightId);
    event MinBoostAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MaxFightsPerEventUpdated(uint256 oldLimit, uint256 newLimit);
    event MaxBonusDepositUpdated(uint256 oldLimit, uint256 newLimit);
    event BonusDeposited(string indexed eventId, uint256 indexed fightId, address indexed manager, uint256 amount);
    event BoostPlaced(
        string indexed eventId,
        uint256 indexed fightId,
        address indexed user,
        uint256 boostIndex,
        uint256 amount,
        Corner winner,
        WinMethod method,
        uint256 timestamp
    );
    event BoostIncreased(
        string indexed eventId,
        uint256 indexed fightId,
        address indexed user,
        uint256 boostIndex,
        uint256 additionalAmount,
        uint256 newTotal,
        uint256 timestamp
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
    event FPUpdated(address indexed oldFP, address indexed newFP);

    // ============ Initializer ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _fp, address admin) public initializer {
        require(_fp != address(0), "fp=0");
        require(admin != address(0), "admin=0");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        FP = FP1155(_fp);
        minBoostAmount = 0; // Default: no minimum
        maxFightsPerEvent = 20; // Default: 20 fights per event
        maxBonusDeposit = 0; // Default: no maximum (0 = unlimited)
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev UUPS upgrade authorization: only DEFAULT_ADMIN_ROLE can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    // ============ Admin Functions ============

    /**
     * @notice Set minimum boost amount (0 to disable)
     * @param newMin New minimum boost amount in FP wei
     */
    function setMinBoostAmount(uint256 newMin) external onlyRole(OPERATOR_ROLE) {
        // Short-circuit if value already matches to avoid redundant storage writes and events
        if (minBoostAmount == newMin) return;
        uint256 oldMin = minBoostAmount;
        minBoostAmount = newMin;
        emit MinBoostAmountUpdated(oldMin, newMin);
    }

    /**
     * @notice Update the FP1155 contract address
     * @param newFP New FP1155 contract address
     * @dev Only DEFAULT_ADMIN_ROLE can update the FP contract.
     *      After updating, ensure the new FP contract grants TRANSFER_AGENT_ROLE to this Booster.
     */
    function setFP(address newFP) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFP != address(0), "fp=0");
        address oldFP = address(FP);
        if (oldFP == newFP) return;
        FP = FP1155(newFP);
        emit FPUpdated(oldFP, newFP);
    }

    /**
     * @notice Set maximum number of fights per event (0 to disable)
     * @param newMax New maximum number of fights per event
     */
    function setMaxFightsPerEvent(uint256 newMax) external onlyRole(OPERATOR_ROLE) {
        // Short-circuit if value already matches to avoid redundant storage writes and events
        if (maxFightsPerEvent == newMax) return;
        uint256 oldMax = maxFightsPerEvent;
        maxFightsPerEvent = newMax;
        emit MaxFightsPerEventUpdated(oldMax, newMax);
    }

    /**
     * @notice Set maximum bonus deposit amount (0 to disable)
     * @param newMax New maximum bonus deposit amount in FP tokens
     */
    function setMaxBonusDeposit(uint256 newMax) external onlyRole(OPERATOR_ROLE) {
        // Short-circuit if value already matches to avoid redundant storage writes and events
        if (maxBonusDeposit == newMax) return;
        uint256 oldMax = maxBonusDeposit;
        maxBonusDeposit = newMax;
        emit MaxBonusDepositUpdated(oldMax, newMax);
    }

    /**
     * @notice Create a new event with multiple fights
     * @param eventId Unique identifier for the event (e.g., "UFC_300")
     * @param numFights Number of fights in the event (fights are 1, 2, 3, ..., numFights)
     * @param seasonId Which FP season this event uses
     * @param defaultBoostCutoff Default boost cutoff timestamp for all fights (0 = no cutoff)
     */
    function createEvent(string calldata eventId, uint256 numFights, uint256 seasonId, uint256 defaultBoostCutoff)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(!events[eventId].exists, "event exists");
        require(numFights > 0, "no fights");
        require(maxFightsPerEvent == 0 || numFights <= maxFightsPerEvent, "numFights exceeds maximum");

        // Verify season is valid and open
        require(FP.seasonStatus(seasonId) == FP1155.SeasonStatus.OPEN, "season not open");

        // Create event
        events[eventId] =
            Event({ seasonId: seasonId, numFights: numFights, exists: true, claimDeadline: 0, claimReady: false });

        // Validate defaultBoostCutoff if provided
        if (defaultBoostCutoff > 0) {
            require(block.timestamp <= defaultBoostCutoff, "boost cutoff must be in the future");
        }

        // Initialize all fights as OPEN (fightIds are 1, 2, 3, ..., numFights) and set boost cutoff if provided
        for (uint256 i = 1; i <= numFights; i++) {
            fights[eventId][i].status = FightStatus.OPEN;
            if (defaultBoostCutoff > 0) {
                fights[eventId][i].boostCutoff = defaultBoostCutoff;
            }
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

        // Short-circuit if value already matches to avoid redundant storage writes and events
        if (fight.boostCutoff == cutoff) return;
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
                // Only update and emit if value actually changed
                if (fight.boostCutoff != cutoff) {
                    fight.boostCutoff = cutoff;
                    emit FightBoostCutoffUpdated(eventId, i, cutoff);
                }
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
        // Short-circuit if value already matches to avoid redundant storage writes and events
        if (current == deadline) return;
        if (current != 0) {
            require(deadline == 0 || deadline >= current, "deadline decrease");
        }
        events[eventId].claimDeadline = deadline;
        emit EventClaimDeadlineUpdated(eventId, deadline);
    }

    /**
     * @notice Set event claim ready state
     * @dev When claimReady is true, fight results cannot be updated and claims are enabled
     *      When claimReady is false, fight results can be updated and claims are disabled.
     *      Setting claimReady to false should NOT be used in normal operations. It is only for
     *      flexibility in case of inconsistent results that need to be corrected before allowing claims.
     * @param eventId Event identifier
     * @param claimReady Whether the event should be claim ready (true) or not (false)
     */
    function setEventClaimReady(string calldata eventId, bool claimReady) external onlyRole(OPERATOR_ROLE) {
        require(events[eventId].exists, "event not exists");
        events[eventId].claimReady = claimReady;
        emit EventClaimReady(eventId, claimReady);
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
            FP.agentTransferFrom(address(this), recipient, evt.seasonId, totalSweep, "");
        }
        emit EventPurged(eventId, recipient, totalSweep);
    }

    // ============ Manager Functions ============

    /**
     * @notice Manager deposits FP bonus to a fight's prize pool
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param amount Amount of FP to deposit as bonus
     * @param force If true, allows deposit even when fight is RESOLVED (for result corrections)
     */
    function depositBonus(string calldata eventId, uint256 fightId, uint256 amount, bool force)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        require(events[eventId].exists, "event not exists");
        require(amount > 0, "amount=0");
        require(maxBonusDeposit == 0 || amount <= maxBonusDeposit, "bonus deposit exceeds maximum");

        Fight storage fight = fights[eventId][fightId];
        // Allow deposit if force is true, otherwise require fight not to be RESOLVED
        require(force || fight.status != FightStatus.RESOLVED, "fight resolved");

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
     * @dev Can be called multiple times to update results until the event is marked as claimReady
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
        // Cannot update results once event is claim ready
        require(!events[eventId].claimReady, "event claim ready");

        Event storage evt = events[eventId];
        _submitFightResult(
            eventId,
            evt,
            fightId,
            winner,
            method,
            pointsForWinner,
            pointsForWinnerMethod,
            sumWinnersStakes,
            winningPoolTotalShares
        );
    }

    /**
     * @notice Server submits multiple fight results in batch
     * @param eventId Event identifier
     * @param inputs Array of fight result inputs
     * @dev Can be called multiple times to update results until the event is marked as claimReady
     *      Each input is validated with the same rules as submitFightResult
     */
    function submitFightResults(string calldata eventId, FightResultInput[] calldata inputs)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(events[eventId].exists, "event not exists");
        // Cannot update results once event is claim ready
        require(!events[eventId].claimReady, "event claim ready");
        require(inputs.length > 0, "no inputs");

        Event storage evt = events[eventId];
        require(inputs.length <= evt.numFights, "too many inputs");

        for (uint256 i = 0; i < inputs.length; i++) {
            FightResultInput calldata input = inputs[i];
            _submitFightResult(
                eventId,
                evt,
                input.fightId,
                input.winner,
                input.method,
                input.pointsForWinner,
                input.pointsForWinnerMethod,
                input.sumWinnersStakes,
                input.winningPoolTotalShares
            );
        }
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
            _validateFightId(evt, input.fightId);

            Fight storage fight = fights[eventId][input.fightId];
            require(fight.status == FightStatus.OPEN, "fight not open");
            require(!fight.cancelled, "fight cancelled");

            _validateBoostCutoff(fight);

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
                input.predictedMethod,
                block.timestamp
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
        _validateFightId(evt, fightId);

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.OPEN, "fight not open");
        require(!fight.cancelled, "fight cancelled");

        _validateBoostCutoff(fight);

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

        emit BoostIncreased(eventId, fightId, msg.sender, boostIndex, additionalAmount, boost.amount, block.timestamp);
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
        require(boostIndices.length > 0, "no boost indices");

        Event storage evt = events[eventId];
        require(evt.claimReady, "event not claim ready");

        uint256 deadline = evt.claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");

        uint256 totalPayout = _processFightClaim(eventId, fightId, boostIndices, msg.sender);

        // Transfer total payout to user
        require(totalPayout > 0, "nothing to claim");
        FP.agentTransferFrom(address(this), msg.sender, evt.seasonId, totalPayout, "");
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
        require(inputs.length <= evt.numFights, "too many inputs");
        require(evt.claimReady, "event not claim ready");
        uint256 deadline = evt.claimDeadline;
        require(deadline == 0 || block.timestamp <= deadline, "claim deadline passed");

        uint256 totalPayout = 0;

        for (uint256 j = 0; j < inputs.length; j++) {
            ClaimInput calldata input = inputs[j];
            require(input.boostIndices.length > 0, "no boost indices");

            totalPayout += _processFightClaim(eventId, input.fightId, input.boostIndices, msg.sender);
        }

        // Transfer total payout to user
        require(totalPayout > 0, "nothing to claim");
        FP.agentTransferFrom(address(this), msg.sender, evt.seasonId, totalPayout, "");
    }

    // ============ View Functions ============

    /**
     * @notice Get event details
     * @param eventId Event identifier
     * @return seasonId The FP season for this event
     * @return numFights Number of fights in the event (fights are 1, 2, 3, ..., numFights)
     * @return exists Whether the event exists
     * @return claimReady Whether the event is in claim ready state (final approval)
     */
    function getEvent(string calldata eventId)
        external
        view
        returns (uint256 seasonId, uint256 numFights, bool exists, bool claimReady)
    {
        Event storage evt = events[eventId];
        return (evt.seasonId, evt.numFights, evt.exists, evt.claimReady);
    }

    /**
     * @notice Get the claim deadline for an event
     */
    function getEventClaimDeadline(string calldata eventId) external view returns (uint256) {
        return events[eventId].claimDeadline;
    }

    /**
     * @notice Check if an event is claim ready
     * @param eventId Event identifier
     * @return Whether the event is in claim ready state
     */
    function isEventClaimReady(string calldata eventId) external view returns (bool) {
        return events[eventId].claimReady;
    }

    /**
     * @notice Get all fights for an event with their statuses
     * @param eventId Event identifier
     * @return fightIds Array of fight IDs (1, 2, 3, ..., numFights)
     * @return statuses Array of fight statuses corresponding to each fight ID
     */
    function getEventFights(string calldata eventId)
        external
        view
        returns (uint256[] memory fightIds, FightStatus[] memory statuses)
    {
        Event storage evt = events[eventId];
        require(evt.exists, "event not exists");

        fightIds = new uint256[](evt.numFights);
        statuses = new FightStatus[](evt.numFights);

        for (uint256 i = 1; i <= evt.numFights; i++) {
            fightIds[i - 1] = i;
            statuses[i - 1] = fights[eventId][i].status;
        }
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
        return _quoteClaimableInternal(eventId, fightId, user, enforceDeadline, false);
    }

    /**
     * @notice Quote historical claimable payout across a set of boosts for a user (includes already claimed boosts).
     * @dev Returns total payout that would have been claimable, including boosts already claimed.
     *      Useful for historical analysis. Does NOT enforce deadline.
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param user User address
     */
    function quoteClaimableHistorical(string calldata eventId, uint256 fightId, address user)
        external
        view
        returns (uint256 totalClaimable)
    {
        return _quoteClaimableInternal(eventId, fightId, user, false, true);
    }

    /**
     * @notice Internal function to calculate claimable payout for boosts
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param user User address
     * @param enforceDeadline Whether to check claim deadline
     * @param includeClaimed Whether to include already claimed boosts in calculation
     * @return totalClaimable Total claimable amount
     */
    function _quoteClaimableInternal(
        string calldata eventId,
        uint256 fightId,
        address user,
        bool enforceDeadline,
        bool includeClaimed
    ) internal view returns (uint256 totalClaimable) {
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
            if (!includeClaimed && boost.claimed) continue;
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
     * @notice Validate that a fightId is within the valid range for an event
     * @param evt Event storage reference
     * @param fightId Fight number to validate
     */
    function _validateFightId(Event storage evt, uint256 fightId) internal view {
        require(fightId >= 1 && fightId <= evt.numFights, "fightId not in event");
    }

    /**
     * @notice Validate that boost cutoff time has not passed
     * @param fight Fight storage reference
     */
    function _validateBoostCutoff(Fight storage fight) internal view {
        if (fight.boostCutoff > 0) {
            require(block.timestamp <= fight.boostCutoff, "boost cutoff passed");
        }
    }

    /**
     * @notice Internal function to validate and store a fight result
     * @param eventId Event identifier
     * @param evt Event storage reference (must be validated before calling)
     * @param fightId Fight number
     * @param winner Which corner won
     * @param method How they won
     * @param pointsForWinner Points awarded for correct winner only
     * @param pointsForWinnerMethod Points awarded for correct winner AND method
     * @param sumWinnersStakes Sum of all winning users' stakes
     * @param winningPoolTotalShares Total shares (sum of points * stakes for all winners)
     */
    function _submitFightResult(
        string calldata eventId,
        Event storage evt,
        uint256 fightId,
        Corner winner,
        WinMethod method,
        uint256 pointsForWinner,
        uint256 pointsForWinnerMethod,
        uint256 sumWinnersStakes,
        uint256 winningPoolTotalShares
    ) internal {
        _validateFightId(evt, fightId);

        // Validate points parameters
        require(pointsForWinner > 0, "points for winner must be > 0");
        require(pointsForWinnerMethod >= pointsForWinner, "method points must be >= winner points");

        // Validate winner/method consistency
        if (winner == Corner.NONE) {
            require(method == WinMethod.NO_CONTEST, "NONE winner requires NO_CONTEST method");
        } else {
            // if there are winners, sumWinnersStakes and winningPoolTotalShares must be > 0
            if (sumWinnersStakes > 0) {
                require(winningPoolTotalShares > 0, "winningPoolTotalShares must be > 0 if sumWinnersStakes > 0");
            }
            if (winningPoolTotalShares > 0) {
                require(sumWinnersStakes > 0, "sumWinnersStakes must be > 0 if winningPoolTotalShares > 0");
            }
        }

        Fight storage fight = fights[eventId][fightId];
        require(!fight.cancelled, "fight cancelled");
        // If there are winners, they must be a subset of all users who placed boosts
        if (sumWinnersStakes > 0) {
            require(sumWinnersStakes <= fight.originalPool, "sumWinnersStakes exceeds originalPool");
        }

        // Store result
        fight.status = FightStatus.RESOLVED;
        fight.winner = winner;
        fight.method = method;
        fight.pointsForWinner = pointsForWinner;
        fight.pointsForWinnerMethod = pointsForWinnerMethod;
        fight.sumWinnersStakes = sumWinnersStakes;
        fight.winningPoolTotalShares = winningPoolTotalShares;

        // Auto-set cancelled flag for no-contest outcomes to enable refunds
        // This ensures consistent behavior whether cancelFight() or submitFightResult()
        // is used to declare a no-contest
        if (winner == Corner.NONE) {
            fight.cancelled = true;
        }

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

    /**
     * @notice Process claim for a single fight
     * @param eventId Event identifier
     * @param fightId Fight number
     * @param boostIndices Array of boost indices to claim
     * @param user Address claiming the reward
     * @return payout Total payout amount for this fight
     */
    function _processFightClaim(string calldata eventId, uint256 fightId, uint256[] calldata boostIndices, address user)
        internal
        returns (uint256 payout)
    {
        _validateFightId(events[eventId], fightId);

        Fight storage fight = fights[eventId][fightId];
        require(fight.status == FightStatus.RESOLVED, "not resolved");

        // Handle cancelled fight (full refund of principal)
        if (fight.cancelled) {
            payout = _processCancelledBoostRefund(boosts[eventId][fightId], boostIndices, user);
            require(payout > 0, "nothing to refund");
            fight.claimedAmount += payout;
            return payout;
        }

        // Normal claim flow (winning boosts)
        // If no winners, return 0 (allows batch claims to skip fights with no winners)
        if (fight.sumWinnersStakes == 0 || fight.winningPoolTotalShares == 0) {
            return 0;
        }

        // Ensure sumWinnersStakes doesn't exceed originalPool (winners are subset of all users)
        require(fight.sumWinnersStakes <= fight.originalPool, "sumWinnersStakes exceeds originalPool");

        uint256 prizePool = fight.originalPool - fight.sumWinnersStakes + fight.bonusPool;
        for (uint256 i = 0; i < boostIndices.length; i++) {
            payout += _processWinningBoostClaim(
                eventId, fightId, fight, boosts[eventId][fightId], boostIndices[i], user, prizePool
            );
        }
        return payout;
    }

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

    // ============ ERC1155 Receiver Implementation ============
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // ============ Interface Support ============
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
