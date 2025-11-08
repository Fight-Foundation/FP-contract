// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FP1155} from "../src/FP1155.sol";

contract DummyAgent {
    FP1155 public immutable FP;
    constructor(FP1155 _fp) { FP = _fp; }
    function pull(address from, address to, uint256 seasonId, uint256 amount) external {
        FP.agentTransferFrom(from, to, seasonId, amount, "");
    }
}

contract FP1155AgentTest is Test {
    FP1155 FP;
    DummyAgent agent;
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant SEASON = 0;

    function setUp() public {
    FP = new FP1155("ipfs://base/{id}.json", admin);
    agent = new DummyAgent(FP);
    FP.grantRole(FP.MINTER_ROLE(), admin);
        // allowlist endpoints that will be used
    FP.setTransferAllowlist(alice, true);
    FP.setTransferAllowlist(bob, true);
    FP.setTransferAllowlist(address(agent), true);
        // mint to alice
    FP.mint(alice, SEASON, 50, "");
    }

    function test_AgentTransfer_SucceedsWithRole() public {
        // grant agent role
    FP.grantRole(FP.TRANSFER_AGENT_ROLE(), address(agent));
        // move 20 from alice to bob without approvals
        vm.prank(address(0xCAFE)); // arbitrary caller; agent is internal caller
        agent.pull(alice, bob, SEASON, 20);
    assertEq(FP.balanceOf(alice, SEASON), 30);
    assertEq(FP.balanceOf(bob, SEASON), 20);
    }

    function test_AgentTransfer_RevertsWithoutRole() public {
        vm.expectRevert();
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsIfUserNotAllowlisted() public {
    FP.grantRole(FP.TRANSFER_AGENT_ROLE(), address(agent));
        // remove alice from allowlist
    FP.setTransferAllowlist(alice, false);
        vm.expectRevert(bytes("transfer: endpoints not allowed"));
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsIfSeasonLocked() public {
    FP.grantRole(FP.TRANSFER_AGENT_ROLE(), address(agent));
    FP.setSeasonStatus(SEASON, FP1155.SeasonStatus.LOCKED);
        vm.expectRevert(bytes("transfer: season locked"));
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsOnZeroAmount() public {
    FP.grantRole(FP.TRANSFER_AGENT_ROLE(), address(agent));
        vm.expectRevert(bytes("amount=0"));
        agent.pull(alice, bob, SEASON, 0);
    }
}
