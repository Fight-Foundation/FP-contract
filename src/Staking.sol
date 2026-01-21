// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeERC20, IERC20 } from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "./../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Pausable } from "./../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "./../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Staking
 * @notice Minimal staking contract for FIGHT tokens
 * @dev All weight calculations should be done off-chain using events and timestamps
 */
contract Staking is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token to stake
    IERC20 public immutable FIGHT_TOKEN;

    // Total amount staked
    uint256 public totalStaked;

    // User balances
    mapping(address => uint256) public balances;

    // Events
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 userBalanceBefore,
        uint256 userBalanceAfter,
        uint256 totalStakedAfter,
        uint256 timestamp,
        uint256 blockNumber
    );
    event Unstaked(
        address indexed user,
        uint256 amount,
        uint256 userBalanceBefore,
        uint256 userBalanceAfter,
        uint256 totalStakedAfter,
        uint256 timestamp,
        uint256 blockNumber
    );

    /**
     * @notice Constructor
     * @param fightToken Address of the FIGHT token
     * @param owner Address of the contract owner
     */
    constructor(address fightToken, address owner) Ownable(owner) {
        require(fightToken.code.length > 0, "Invalid token");
        FIGHT_TOKEN = IERC20(fightToken);
    }

    /**
     * @notice Stake FIGHT tokens
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Zero amount");

        uint256 userBalanceBefore = balances[msg.sender];
        balances[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(
            msg.sender, amount, userBalanceBefore, balances[msg.sender], totalStaked, block.timestamp, block.number
        );

        FIGHT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Unstake FIGHT tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 userBalanceBefore = balances[msg.sender];
        balances[msg.sender] -= amount;
        totalStaked -= amount;

        emit Unstaked(
            msg.sender, amount, userBalanceBefore, balances[msg.sender], totalStaked, block.timestamp, block.number
        );

        FIGHT_TOKEN.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
