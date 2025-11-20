// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { FP1155 } from "src/FP1155.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Pausable } from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import { MessageHashUtils } from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract FP1155Test is Test {
    FP1155 fp;

    address admin = address(this);
    address minter = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xC0C);
    address agent = address(0xD00D);
    address serverSigner; // address derived from a private key used to sign claims

    uint256 serverPk = 0xBEEF; // test-only private key for claim signer

    uint256 constant S1 = 2501; // Season 25.01

    function setUp() public {
        // Deploy implementation
        FP1155 implementation = new FP1155();
        // Initialize via proxy
        bytes memory initData = abi.encodeWithSelector(FP1155.initialize.selector, "ipfs://base/{id}.json", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        fp = FP1155(address(proxy));
        // grant roles
        vm.prank(admin);
        fp.grantRole(fp.MINTER_ROLE(), minter);
        vm.prank(admin);
        fp.grantRole(fp.TRANSFER_AGENT_ROLE(), agent);

        // set up claim signer role
        serverSigner = vm.addr(serverPk);
        vm.prank(admin);
        fp.grantRole(fp.CLAIM_SIGNER_ROLE(), serverSigner);
    }

    function _mintToAlice(uint256 id, uint256 amt) internal {
        vm.prank(minter);
        fp.mint(alice, id, amt, "");
    }

    function testMintWithMinter() public {
        _mintToAlice(S1, 10);
        assertEq(fp.balanceOf(alice, S1), 10);
    }

    function testMintFailsWhenLocked() public {
        // lock season
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        vm.startPrank(minter);
        vm.expectRevert(bytes("mint: season locked"));
        fp.mint(alice, S1, 1, "");
        vm.stopPrank();
    }

    function testTransferRequiresAllowlist() public {
        _mintToAlice(S1, 5);
        // allow both endpoints
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);

        vm.prank(alice);
        fp.safeTransferFrom(alice, bob, S1, 2, "");
        assertEq(fp.balanceOf(alice, S1), 3);
        assertEq(fp.balanceOf(bob, S1), 2);
    }

    function testTransferFailsIfEndpointNotAllowed() public {
        _mintToAlice(S1, 5);
        // only alice allowed, bob not
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(bytes("transfer: endpoints not allowed"));
        fp.safeTransferFrom(alice, bob, S1, 1, "");
        vm.stopPrank();
    }

    function testTransferAllowedWithAgentAndAllowlist() public {
        // mint to agent and send to allowlisted bob
        vm.prank(minter);
        fp.mint(agent, S1, 4, "");
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);

        vm.prank(agent);
        fp.safeTransferFrom(agent, bob, S1, 1, "");
        assertEq(fp.balanceOf(agent, S1), 3);
        assertEq(fp.balanceOf(bob, S1), 1);
    }

    function testBurnAllowedWhenLocked() public {
        _mintToAlice(S1, 2);
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);

        vm.prank(alice);
        fp.burn(alice, S1, 1);
        assertEq(fp.balanceOf(alice, S1), 1);
    }

    function testPauseBlocksMintTransferBurn() public {
        // prepare balances before pausing
        _mintToAlice(S1, 1);
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);

        vm.prank(admin);
        fp.pause();

        // mint should be blocked while paused
        vm.startPrank(minter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fp.mint(alice, S1, 1, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fp.safeTransferFrom(alice, bob, S1, 1, "");
        vm.stopPrank();

        // burn
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fp.burn(alice, S1, 1);
    }

    function testSeasonLockIsIrreversible() public {
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        vm.prank(admin);
        vm.expectRevert(bytes("locked: irreversible"));
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.OPEN);
    }

    function testOnlyAdminCanSetURI() public {
        // sanity check: minter is not admin
        assertFalse(fp.hasRole(fp.DEFAULT_ADMIN_ROLE(), minter));
        // non-admin tries
        vm.prank(minter);
        vm.expectRevert();
        fp.setURI("ipfs://hacker/{id}.json");

        // admin ok
        vm.prank(admin);
        fp.setURI("ipfs://new/{id}.json");
        // basic read via uri() uses string replacement client-side, so here we just ensure no revert
    }

    function testBatchMintAndTransfer() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = S1;
        ids[1] = S1 + 1; // another season defaults OPEN
        uint256[] memory amts = new uint256[](2);
        amts[0] = 3;
        amts[1] = 7;

        vm.prank(minter);
        fp.mintBatch(alice, ids, amts, "");
        assertEq(fp.balanceOf(alice, ids[0]), 3);
        assertEq(fp.balanceOf(alice, ids[1]), 7);

        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);

        vm.startPrank(alice);
        fp.safeBatchTransferFrom(alice, bob, ids, amts, "");
        vm.stopPrank();

        assertEq(fp.balanceOf(alice, ids[0]), 0);
        assertEq(fp.balanceOf(alice, ids[1]), 0);
        assertEq(fp.balanceOf(bob, ids[0]), 3);
        assertEq(fp.balanceOf(bob, ids[1]), 7);
    }

    // ------- Claims -------
    function _signClaim(address account, uint256 id, uint256 amt, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 typehash = fp.CLAIM_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(typehash, account, id, amt, nonce, deadline));
        bytes32 digest = MessageHashUtils.toTypedDataHash(fp.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(serverPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function testClaimHappyPath() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 7, nonce, deadline);

        vm.prank(alice);
        fp.claim(S1, 7, deadline, sig);
        assertEq(fp.balanceOf(alice, S1), 7);
        assertEq(fp.nonces(alice), nonce + 1);
    }

    function testClaimWrongSignerReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        // sign with a different key (not granted CLAIM_SIGNER_ROLE)
        uint256 badPk = 0xDEAD;
        bytes32 typehash = fp.CLAIM_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(typehash, alice, S1, 3, nonce, deadline));
        bytes32 digest = MessageHashUtils.toTypedDataHash(fp.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(bytes("claim: invalid signer"));
        fp.claim(S1, 3, deadline, badSig);
    }

    function testClaimExpiredReverts() public {
        uint256 deadline = block.timestamp - 1; // already expired
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 2, nonce, deadline);
        vm.prank(alice);
        vm.expectRevert(bytes("claim: expired"));
        fp.claim(S1, 2, deadline, sig);
    }

    function testClaimReplayBlockedByNonce() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 5, nonce, deadline);

        vm.prank(alice);
        fp.claim(S1, 5, deadline, sig);
        assertEq(fp.balanceOf(alice, S1), 5);

        // replay with same signature should fail due to nonce mismatch
        vm.prank(alice);
        // The signature will now be invalid for the incremented nonce; expect revert on invalid signer
        vm.expectRevert();
        fp.claim(S1, 5, deadline, sig);
    }

    function testTransferFailsWhenSeasonLocked() public {
        _mintToAlice(S1, 3);
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        // lock the season
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        vm.startPrank(alice);
        vm.expectRevert(bytes("transfer: season locked"));
        fp.safeTransferFrom(alice, bob, S1, 1, "");
        vm.stopPrank();
    }

    function testClaimFailsWhenSeasonLocked() public {
        // lock season first
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 2, nonce, deadline);
        vm.prank(alice);
        vm.expectRevert(bytes("claim: season locked"));
        fp.claim(S1, 2, deadline, sig);
    }

    function testClaimBlockedWhenPaused() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 2, nonce, deadline);
        vm.prank(admin);
        fp.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fp.claim(S1, 2, deadline, sig);
    }

    function testBurnBatchAllowedWhenLocked() public {
        // mint two seasons
        uint256[] memory ids = new uint256[](2);
        ids[0] = S1;
        ids[1] = S1 + 1;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 2;
        amts[1] = 3;
        vm.prank(minter);
        fp.mintBatch(alice, ids, amts, "");
        // lock both
        vm.prank(admin);
        fp.setSeasonStatus(ids[0], FP1155.SeasonStatus.LOCKED);
        vm.prank(admin);
        fp.setSeasonStatus(ids[1], FP1155.SeasonStatus.LOCKED);
        // burnBatch should succeed when LOCKED
        vm.prank(alice);
        fp.burnBatch(alice, ids, amts);
        assertEq(fp.balanceOf(alice, ids[0]), 0);
        assertEq(fp.balanceOf(alice, ids[1]), 0);
    }

    function testSetSeasonStatusRequiresRole() public {
        // minter does not have season admin role
        vm.prank(minter);
        vm.expectRevert();
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
    }

    function testTransferToAgentAllowsNonAllowlistedSender() public {
        // New behavior: if destination has TRANSFER_AGENT_ROLE, sender doesn't need to be allowlisted
        _mintToAlice(S1, 5);
        // agent already has TRANSFER_AGENT_ROLE from setUp; alice is NOT allowlisted
        vm.prank(alice);
        fp.safeTransferFrom(alice, agent, S1, 3, "");
        assertEq(fp.balanceOf(alice, S1), 2);
        assertEq(fp.balanceOf(agent, S1), 3);
    }

    function testTransferToAgentStillRequiresOpenSeason() public {
        _mintToAlice(S1, 2);
        // Lock the season
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        // Even though destination is agent, season must be OPEN
        vm.startPrank(alice);
        vm.expectRevert(bytes("transfer: season locked"));
        fp.safeTransferFrom(alice, agent, S1, 1, "");
        vm.stopPrank();
    }

    function testTransferToNonAgentStillRequiresBothEndpointsAllowed() public {
        _mintToAlice(S1, 3);
        // Only allowlist bob, not alice
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        // alice is not allowlisted, so transfer should fail even though bob is allowlisted
        vm.startPrank(alice);
        vm.expectRevert(bytes("transfer: endpoints not allowed"));
        fp.safeTransferFrom(alice, bob, S1, 1, "");
        vm.stopPrank();
    }

    function testBatchTransferToAgentAllowsNonAllowlistedSender() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = S1;
        ids[1] = S1 + 1;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 2;
        amts[1] = 3;
        vm.prank(minter);
        fp.mintBatch(alice, ids, amts, "");
        // alice is NOT allowlisted, but agent has TRANSFER_AGENT_ROLE
        vm.prank(alice);
        fp.safeBatchTransferFrom(alice, agent, ids, amts, "");
        assertEq(fp.balanceOf(alice, ids[0]), 0);
        assertEq(fp.balanceOf(alice, ids[1]), 0);
        assertEq(fp.balanceOf(agent, ids[0]), 2);
        assertEq(fp.balanceOf(agent, ids[1]), 3);
    }

    function testTransferFromAgentToNonAllowlistedFails() public {
        // This test is now obsolete - agents CAN transfer to non-allowlisted users
        // This is required for the Booster contract to pay out rewards
        // Mint to agent
        vm.prank(minter);
        fp.mint(agent, S1, 5, "");
        // bob is NOT allowlisted, but agent can transfer to him
        vm.prank(agent);
        fp.safeTransferFrom(agent, bob, S1, 2, "");
        // Verify transfer succeeded
        assertEq(fp.balanceOf(bob, S1), 2);
    }

    function testTransferFromAgentToAllowlistedSucceeds() public {
        // Mint to agent
        vm.prank(minter);
        fp.mint(agent, S1, 5, "");
        // Allowlist bob
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        // Agent can transfer to allowlisted bob
        vm.prank(agent);
        fp.safeTransferFrom(agent, bob, S1, 2, "");
        assertEq(fp.balanceOf(agent, S1), 3);
        assertEq(fp.balanceOf(bob, S1), 2);
    }

    // ------- Additional coverage -------
    function testUnpauseRestoresOperations() public {
        // prepare a valid claim
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 1, nonce, deadline);

        vm.prank(admin);
        fp.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fp.claim(S1, 1, deadline, sig);

        vm.prank(admin);
        fp.unpause();
        vm.prank(alice);
        fp.claim(S1, 1, deadline, sig);
        assertEq(fp.balanceOf(alice, S1), 1);
    }

    function testIsTransfersAllowedView() public {
        uint256 S2 = S1 + 1; // Use a different season for agent tests
        // mint path (from=0)
        assertTrue(fp.isTransfersAllowed(address(0), alice, S1));
        // burn path (to=0)
        assertTrue(fp.isTransfersAllowed(alice, address(0), S1));
        // transfer path needs allowlist and OPEN
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        assertTrue(fp.isTransfersAllowed(alice, bob, S1));
        // lock and verify false
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        assertFalse(fp.isTransfersAllowed(alice, bob, S1));
        // Use S2 (still OPEN) for agent tests
        // transfer to agent: alice doesn't need to be allowlisted
        assertTrue(fp.isTransfersAllowed(alice, agent, S2));
        // Remove bob from allowlist to test non-allowlisted destination
        vm.prank(admin);
        fp.setTransferAllowlist(bob, false);
        // transfer from agent to non-allowlisted bob should fail
        assertFalse(fp.isTransfersAllowed(agent, bob, S2));
        // Add bob back to allowlist
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        // transfer from agent to allowlisted bob should succeed
        assertTrue(fp.isTransfersAllowed(agent, bob, S2));
    }

    function testBatchTransferRevertsIfAnySeasonLocked() public {
        // mint two seasons to alice
        uint256[] memory ids = new uint256[](2);
        ids[0] = S1;
        ids[1] = S1 + 1;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1;
        amts[1] = 1;
        vm.prank(minter);
        fp.mintBatch(alice, ids, amts, "");
        // allowlist
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(bob, true);
        // lock one id
        vm.prank(admin);
        fp.setSeasonStatus(ids[1], FP1155.SeasonStatus.LOCKED);
        vm.startPrank(alice);
        vm.expectRevert(bytes("transfer: season locked"));
        fp.safeBatchTransferFrom(alice, bob, ids, amts, "");
        vm.stopPrank();
    }

    function testEventsSeasonStatusAndAllowlist() public {
        // SeasonStatusUpdated
        vm.expectEmit(true, false, false, true);
        emit FP1155.SeasonStatusUpdated(S1, FP1155.SeasonStatus.LOCKED);
        vm.prank(admin);
        fp.setSeasonStatus(S1, FP1155.SeasonStatus.LOCKED);
        // AllowlistUpdated
        vm.expectEmit(true, false, false, true);
        emit FP1155.AllowlistUpdated(alice, true);
        vm.prank(admin);
        fp.setTransferAllowlist(alice, true);
    }

    function testClaimProcessedEventEmitted() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 2, nonce, deadline);
        vm.expectEmit(true, true, false, true);
        emit FP1155.ClaimProcessed(alice, S1, 2, nonce);
        vm.prank(alice);
        fp.claim(S1, 2, deadline, sig);
    }

    function testZeroAmountRevertsClaimMintAndMintBatch() public {
        // claim amount=0
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fp.nonces(alice);
        bytes memory sig = _signClaim(alice, S1, 0, nonce, deadline);
        vm.prank(alice);
        vm.expectRevert(bytes("amount=0"));
        fp.claim(S1, 0, deadline, sig);

        // mint amount=0
        vm.prank(minter);
        vm.expectRevert(bytes("amount=0"));
        fp.mint(alice, S1, 0, "");

        // mintBatch containing zero
        uint256[] memory ids = new uint256[](2);
        ids[0] = S1;
        ids[1] = S1 + 1;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 1;
        amts[1] = 0;
        vm.prank(minter);
        vm.expectRevert(bytes("amount=0"));
        fp.mintBatch(alice, ids, amts, "");
    }
}
