// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FP1155} from "../src/FP1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DummyAgent {
    FP1155 public immutable fp;
    constructor(FP1155 _fp) { fp = _fp; }
    function pull(address from, address to, uint256 seasonId, uint256 amount) external {
        fp.agentTransferFrom(from, to, seasonId, amount, "");
    }
}

contract FP1155AgentTest is Test {
    FP1155 fp;
    DummyAgent agent;
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant SEASON = 0;

    function setUp() public {
        // Deploy implementation and proxy-initialize
        FP1155 implementation = new FP1155();
        bytes memory initData = abi.encodeWithSelector(
            FP1155.initialize.selector,
            "ipfs://base/{id}.json",
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        fp = FP1155(address(proxy));
        agent = new DummyAgent(fp);
        fp.grantRole(fp.MINTER_ROLE(), admin);
        // allowlist endpoints that will be used
        fp.setTransferAllowlist(alice, true);
        fp.setTransferAllowlist(bob, true);
        fp.setTransferAllowlist(address(agent), true);
        // mint to alice
        fp.mint(alice, SEASON, 50, "");
    }

    function test_AgentTransfer_SucceedsWithRole() public {
        // grant agent role
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(agent));
        // move 20 from alice to bob without approvals
        vm.prank(address(0xCAFE)); // arbitrary caller; agent is internal caller
        agent.pull(alice, bob, SEASON, 20);
        assertEq(fp.balanceOf(alice, SEASON), 30);
        assertEq(fp.balanceOf(bob, SEASON), 20);
    }

    function test_AgentTransfer_RevertsWithoutRole() public {
        vm.expectRevert();
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsIfUserNotAllowlisted() public {
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(agent));
        // remove alice from allowlist
        fp.setTransferAllowlist(alice, false);
        vm.expectRevert(bytes("transfer: endpoints not allowed"));
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsIfSeasonLocked() public {
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(agent));
        fp.setSeasonStatus(SEASON, FP1155.SeasonStatus.LOCKED);
        vm.expectRevert(bytes("transfer: season locked"));
        agent.pull(alice, bob, SEASON, 1);
    }

    function test_AgentTransfer_RevertsOnZeroAmount() public {
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), address(agent));
        vm.expectRevert(bytes("amount=0"));
        agent.pull(alice, bob, SEASON, 0);
    }
}
