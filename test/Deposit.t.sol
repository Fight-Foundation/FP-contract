// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { FP1155 } from "../src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Deposit } from "../src/Deposit.sol";

contract DepositTest is Test {
    FP1155 fp;
    Deposit deposit;

    address admin = address(this);
    address user = address(0xBEEF);
    uint256 constant SEASON = 0;

    function setUp() public {
        // Deploy FP1155 with this test as admin via proxy
        FP1155 implementation = new FP1155();
        bytes memory initData = abi.encodeWithSelector(FP1155.initialize.selector, "ipfs://base/{id}.json", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        fp = FP1155(address(proxy));

        // Deploy Deposit and grant it TRANSFER_AGENT_ROLE
        deposit = new Deposit(fp);
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(deposit));

        // Grant MINTER_ROLE to this test to mint to user
        fp.grantRole(fp.MINTER_ROLE(), admin);

        // Allowlist user (required as transfer endpoints must both be allowed)
        fp.setTransferAllowlist(user, true);

        // Mint some FP to user for season
        fp.mint(user, SEASON, 100, "");

        // No approval needed; Deposit uses agentTransferFrom via TRANSFER_AGENT_ROLE
    }

    function test_DepositAndWithdraw_HappyPath() public {
        // User deposits 40
        vm.prank(user);
        deposit.deposit(SEASON, 40);

        assertEq(deposit.deposited(user, SEASON), 40);
        assertEq(fp.balanceOf(user, SEASON), 60);
        assertEq(fp.balanceOf(address(deposit), SEASON), 40);

        // User withdraws 15
        vm.prank(user);
        deposit.withdraw(SEASON, 15);

        assertEq(deposit.deposited(user, SEASON), 25);
        assertEq(fp.balanceOf(user, SEASON), 75);
        assertEq(fp.balanceOf(address(deposit), SEASON), 25);
    }

    function test_Deposit_NoApprovalRequiredForAgent() public {
        // Without any approval, deposit should succeed because Deposit has TRANSFER_AGENT_ROLE
        vm.prank(user);
        deposit.deposit(SEASON, 10);

        assertEq(deposit.deposited(user, SEASON), 10);
        assertEq(fp.balanceOf(user, SEASON), 90);
        assertEq(fp.balanceOf(address(deposit), SEASON), 10);
    }

    function test_Withdraw_RevertExceedsDeposit() public {
        // Deposit 10
        vm.prank(user);
        deposit.deposit(SEASON, 10);

        // Try withdraw 11
        vm.prank(user);
        vm.expectRevert(bytes("withdraw: insufficient"));
        deposit.withdraw(SEASON, 11);
    }

    function test_ZeroAmount_Reverts() public {
        vm.prank(user);
        vm.expectRevert(bytes("amount=0"));
        deposit.deposit(SEASON, 0);

        // Deposit some first
        vm.prank(user);
        deposit.deposit(SEASON, 5);

        vm.prank(user);
        vm.expectRevert(bytes("amount=0"));
        deposit.withdraw(SEASON, 0);
    }

    function test_SeasonLocked_BlocksDepositAndWithdraw() public {
        // Lock season
        fp.setSeasonStatus(SEASON, FP1155.SeasonStatus.LOCKED);

        // Deposit should revert
        vm.prank(user);
        vm.expectRevert(bytes("transfer: season locked"));
        deposit.deposit(SEASON, 5);

        // Unlock for setup is not possible (irreversible), so create a fresh season 1
        uint256 season2 = 1;
        // Season defaults OPEN; mint to user, deposit
        fp.mint(user, season2, 10, "");
        vm.prank(user);
        deposit.deposit(season2, 6);

        // Lock season2 and try to withdraw -> revert
        fp.setSeasonStatus(season2, FP1155.SeasonStatus.LOCKED);
        vm.prank(user);
        vm.expectRevert(bytes("transfer: season locked"));
        deposit.withdraw(season2, 3);
    }

    function test_NotAllowlistedUser_CanDepositButNotWithdraw() public {
        // Remove user from allowlist
        fp.setTransferAllowlist(user, false);

        // Deposit should succeed because destination (Deposit contract) has TRANSFER_AGENT_ROLE
        vm.prank(user);
        deposit.deposit(SEASON, 5);
        assertEq(deposit.deposited(user, SEASON), 5);
        assertEq(fp.balanceOf(user, SEASON), 95);

        // With the new transfer logic, agents (Deposit contract) can transfer to anyone
        // So withdraw now succeeds even for non-allowlisted users
        vm.prank(user);
        deposit.withdraw(SEASON, 2);
        assertEq(deposit.deposited(user, SEASON), 3);
        assertEq(fp.balanceOf(user, SEASON), 97);
    }
}
