// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "./../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Pausable } from "./../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

contract SimpleStaking is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    // interfaces
    IERC20 internal immutable FIGHT_TOKEN;
    // startTime
    uint256 internal immutable _startTime;

    // pool data
    uint256 internal _totalStaked;
    uint256 internal _totalCumulativeWeight;
    uint256 internal _poolLastUpdateTimestamp;

    struct Data {
        uint256 amount;
        uint256 cumulativeWeight;
        uint256 lastUpdateTimestamp;
    }

    mapping(address user => Data userData) internal _users;

    address internal _updater;

    // events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event StakedBehalf(address[] indexed users, uint256[] indexed amounts);

    constructor(address fightToken, uint256 startTime_, address owner, address updater) Ownable(owner) {
        // ensure startTime is not far-dated
        require(startTime_ <= block.timestamp + 30 days, "Far-dated start");
        require(startTime_ >= block.timestamp, "StartTime in past");

        FIGHT_TOKEN = IERC20(fightToken);

        _startTime = startTime_;

        _updater = updater;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice User to stake FIGHT tokens
     * @dev User can stake for another address of choice
     * @param amount Tokens to stake, 1e18 precision
     */
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Zero amount");

        // cache
        Data memory userData_ = _users[msg.sender];

        // book pool's previous
        _updatePool();

        // book user's previous
        Data memory userData = _updateUserCumulativeWeight(userData_);

        // book inflow
        userData.amount += amount;
        _totalStaked += amount;

        // user: update storage
        _users[msg.sender] = userData;

        emit Staked(msg.sender, amount);

        // grab FIGHT
        FIGHT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice User to unstake FIGHT tokens
     * @param amount Tokens to unstake, 1e18 precision
     */
    function unstake(uint256 amount) external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0, "Zero amount");

        // cache
        Data memory userData_ = _users[msg.sender];

        // sanity checks
        require(userData_.amount >= amount, "Insufficient balance");

        // book pool's previous
        _updatePool();

        // book user's previous
        Data memory userData = _updateUserCumulativeWeight(userData_);

        // book outflow
        userData.amount -= amount;
        _totalStaked -= amount; // sstore

        // user: update state
        _users[msg.sender] = userData;

        emit Unstaked(msg.sender, amount);

        // transfer FIGHT
        FIGHT_TOKEN.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Owner to stake on behalf of users for distribution
     * @dev Gas used: 84,805 for length =1, incrementing by 2600 for every additional loop
     * @param users Array of address
     * @param amounts Array of stake amounts, 1e18 precision
     */
    function stakeBehalf(address[] calldata users, uint256[] calldata amounts) external whenNotPaused {
        require(msg.sender == _updater, "Incorrect caller");

        uint256 usersLength = users.length;
        uint256 amountLength = amounts.length;
        require(usersLength == amountLength, "Incorrect lengths");

        require(usersLength > 0, "Empty array");

        // book pool's previous
        _updatePool();

        uint256 totalAmount;
        for (uint256 i; i < usersLength; ++i) {
            address onBehalfOf = users[i];
            uint256 amount = amounts[i];

            // cache
            Data memory userData_ = _users[onBehalfOf];

            // book user's previous
            Data memory userData = _updateUserCumulativeWeight(userData_);

            // book inflow
            userData.amount += amount;

            // user: update storage
            _users[onBehalfOf] = userData;

            // increment totalAmount
            totalAmount += amount;
        }

        emit StakedBehalf(users, amounts);

        _totalStaked += totalAmount; //sstore

        // grab FIGHT
        FIGHT_TOKEN.safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    /**
     * @notice Owner to pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Owner to unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Owner to change updater address
     * @param newUpdater new updater address
     */
    function changeUpdater(address newUpdater) external onlyOwner {
        _updater = newUpdater;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _updatePool() internal {
        // no update of the _poolLastUpdateTimestamp otherwise it can be set to before
        // _poolLastUpdateTimestamp =0, when t = startTime
        if (block.timestamp <= _startTime) {
            return;
        }

        if (_totalStaked > 0) {
            if (block.timestamp > _poolLastUpdateTimestamp) {
                uint256 timeDelta = _getTimeDelta(block.timestamp, _poolLastUpdateTimestamp);
                uint256 unbookedWeight = timeDelta * _totalStaked;

                // sstore
                _totalCumulativeWeight += unbookedWeight;
            }
        }

        // sstore
        _poolLastUpdateTimestamp = block.timestamp;
    }

    function _updateUserCumulativeWeight(Data memory userData) internal returns (Data memory) {
        // staking not started: return early
        uint256 startTime = _startTime;
        if (block.timestamp <= startTime) {
            return userData;
        }

        // staking has begun
        if (userData.amount > 0) {
            if (block.timestamp > userData.lastUpdateTimestamp) {
                // timeDelta: 0 if staking has not begun
                uint256 timeDelta = _getTimeDelta(block.timestamp, userData.lastUpdateTimestamp);
                uint256 unbookedWeight = timeDelta * userData.amount;

                // update user
                userData.cumulativeWeight += unbookedWeight;
            }
        }

        userData.lastUpdateTimestamp = block.timestamp;
        return userData;
    }

    function _getTimeDelta(uint256 to, uint256 from) internal view returns (uint256) {
        // cache
        uint256 startTime = _startTime;

        if (from < startTime) {
            from = startTime;
        }

        return (to - from);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    ///@notice returns FIGHT token address
    function getFightToken() external view returns (address) {
        return address(FIGHT_TOKEN);
    }

    ///@notice returns _startTime
    function getStartTime() external view returns (uint256) {
        return _startTime;
    }

    ///@notice returns _totalStaked
    function getTotalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    ///@notice returns _totalCumulativeWeight
    function getTotalCumulativeWeight() external view returns (uint256) {
        return _totalCumulativeWeight;
    }

    ///@notice returns _poolLastUpdateTimestamp
    function getPoolLastUpdateTimestamp() external view returns (uint256) {
        return _poolLastUpdateTimestamp;
    }

    ///@notice returns user data struct
    function getUser(address user) external view returns (Data memory) {
        return _users[user];
    }

    ///@notice returns user's cumulative weight
    ///@dev returns 0 if staking has not begun
    function getUserCumulativeWeight(address user) external view returns (uint256) {
        // cache
        Data memory userData = _users[user];

        // staking not started: return early
        if (block.timestamp <= _startTime) {
            return 0;
        }

        // calc. unbooked
        if (userData.amount > 0) {
            if (block.timestamp > userData.lastUpdateTimestamp) {
                uint256 timeDelta = _getTimeDelta(block.timestamp, userData.lastUpdateTimestamp);

                uint256 unbookedWeight = userData.amount * timeDelta;
                return (userData.cumulativeWeight + unbookedWeight);
            }
        }

        // updated to latest, nothing unbooked
        return userData.cumulativeWeight;
    }

    ///@notice returns pool's total cumulative weight (incl. pending)
    ///@dev returns 0 if staking has not begun
    function getPoolCumulativeWeight() external view returns (uint256) {
        // staking not started
        if (block.timestamp <= _startTime) {
            return 0;
        }

        // calc. unbooked
        if (block.timestamp > _poolLastUpdateTimestamp) {
            uint256 timeDelta = _getTimeDelta(block.timestamp, _poolLastUpdateTimestamp);

            uint256 unbookedWeight = _totalStaked * timeDelta;
            return (_totalCumulativeWeight + unbookedWeight);
        }

        // updated to latest, nothing unbooked
        return _totalCumulativeWeight;
    }

    ///@notice returns _updater
    function getUpdater() external view returns (address) {
        return _updater;
    }
}
