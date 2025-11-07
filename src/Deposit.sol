// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {FP1155} from "./FP1155.sol";
import {ERC1155Holder} from "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @title Deposit (sample integration)
 * @notice Example helper contract that can hold FP1155 tokens on behalf of users.
 *         Users deposit/withdraw FP for a given season id into/from this contract.
 *         This contract should be granted TRANSFER_AGENT_ROLE in FP1155 so that
 *         endpoint allowlist checks pass for transfers to/from this contract.
 *
 *         IMPORTANT: Users must also setApprovalForAll(this, true) on FP1155 to
 *         allow this contract to move their tokens when depositing.
 */
contract Deposit is ERC1155Holder {
    FP1155 public immutable fp;

    // user => seasonId => deposited balance held by this contract
    mapping(address => mapping(uint256 => uint256)) public deposited;

    event Deposited(address indexed user, uint256 indexed seasonId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed seasonId, uint256 amount);

    constructor(FP1155 _fp) {
        fp = _fp;
    }

    /**
     * @notice Deposit FP of the current season into this contract custody.
     * @dev Requires prior setApprovalForAll to this contract on FP1155.
     *      FP1155 must have season OPEN and endpoints allowed (user and this).
     */
    function deposit(uint256 seasonId, uint256 amount) external {
        require(amount > 0, "amount=0");
    // Agent pull without user approval; relies on TRANSFER_AGENT_ROLE granted to this contract
    fp.agentTransferFrom(msg.sender, address(this), seasonId, amount, "");
        deposited[msg.sender][seasonId] += amount;
        emit Deposited(msg.sender, seasonId, amount);
    }

    /**
     * @notice Withdraw previously deposited FP back to the user.
     * @dev FP1155 must allow transfers (season OPEN and endpoints allowed).
     */
    function withdraw(uint256 seasonId, uint256 amount) external {
        require(amount > 0, "amount=0");
        uint256 bal = deposited[msg.sender][seasonId];
        require(bal >= amount, "withdraw: insufficient");
        deposited[msg.sender][seasonId] = bal - amount;
        // Transfer from this contract back to user
        fp.safeTransferFrom(address(this), msg.sender, seasonId, amount, "");
        emit Withdrawn(msg.sender, seasonId, amount);
    }
}
