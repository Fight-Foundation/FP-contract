// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title FIGHT Token
 * @notice ERC20 token for testing SimpleStaking contract
 * @dev Mintable by owner for testing purposes
 */
contract FIGHT is ERC20, Ownable {
    constructor(address initialOwner) ERC20("FIGHT", "FIGHT") Ownable(initialOwner) {
        // Deployer can mint tokens for testing
    }

    /**
     * @notice Mint tokens to an address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint (1e18 precision)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

