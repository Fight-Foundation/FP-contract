// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FP1155} from "src/FP1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title FP1155 Upgrade Tests
 * @notice Tests for UUPS upgradeability of FP1155
 */
contract FP1155UpgradeTest is Test, IERC1155Receiver {
    FP1155 implementation;
    FP1155 proxy;
    address admin = address(this);
    address user = address(0xBEEF);
    address nonAdmin = address(0xBAD);

    uint256 constant SEASON = 2501;

    function setUp() public {
        // Deploy implementation
        implementation = new FP1155();

        // Encode initializer call
        bytes memory initData = abi.encodeWithSelector(
            FP1155.initialize.selector,
            "ipfs://base/{id}.json",
            admin
        );

        // Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = FP1155(address(proxyContract));

        // Setup: grant roles and allowlist
        proxy.grantRole(proxy.MINTER_ROLE(), admin);
        proxy.setTransferAllowlist(user, true);
        proxy.setTransferAllowlist(admin, true); // Admin needs to be allowlisted too
    }

    // ============ Basic Functionality Tests ============

    function test_ProxyInitialization() public {
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(proxy.hasRole(proxy.PAUSER_ROLE(), admin), true);
        assertEq(proxy.hasRole(proxy.SEASON_ADMIN_ROLE(), admin), true);
    }

    function test_ProxyCanMintAndTransfer() public {
        // Mint to user
        proxy.mint(user, SEASON, 100, "");
        assertEq(proxy.balanceOf(user, SEASON), 100);

        // Transfer
        vm.prank(user);
        proxy.safeTransferFrom(user, admin, SEASON, 50, "");
        assertEq(proxy.balanceOf(user, SEASON), 50);
        assertEq(proxy.balanceOf(admin, SEASON), 50);
    }

    function test_StatePersistedAcrossProxyAndImplementation() public {
        // Mint through proxy
        proxy.mint(user, SEASON, 100, "");

        // Verify state is in proxy, not implementation
        assertEq(proxy.balanceOf(user, SEASON), 100);
        assertEq(implementation.balanceOf(user, SEASON), 0); // Implementation has no state
    }

    // ============ Upgrade Authorization Tests ============

    function test_OnlyAdminCanUpgrade() public {
        FP1155 newImplementation = new FP1155();

        // Non-admin cannot upgrade
        vm.prank(nonAdmin);
        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Admin can upgrade
        proxy.upgradeToAndCall(address(newImplementation), "");
    }

    function test_UpgradeEmitsEvent() public {
        FP1155 newImplementation = new FP1155();

        // Should emit Upgraded event from ERC1967
        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(newImplementation));
        proxy.upgradeToAndCall(address(newImplementation), "");
    }

    // ============ State Preservation Tests ============

    function test_UpgradePreservesState() public {
        // Setup initial state
        proxy.mint(user, SEASON, 100, "");
        proxy.setTransferAllowlist(nonAdmin, true);
        uint256 nonceBefore = proxy.nonces(user);

        // Upgrade to new implementation
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify all state is preserved
        assertEq(proxy.balanceOf(user, SEASON), 100, "Balance not preserved");
        assertEq(proxy.isOnAllowlist(nonAdmin), true, "Allowlist not preserved");
        assertEq(proxy.nonces(user), nonceBefore, "Nonce not preserved");
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin), true, "Admin role not preserved");
    }

    function test_UpgradePreservesRoles() public {
        address minter = address(0xA11CE);
        address agent = address(0xB0B);

        // Grant roles before upgrade
        proxy.grantRole(proxy.MINTER_ROLE(), minter);
        proxy.grantRole(proxy.TRANSFER_AGENT_ROLE(), agent);

        // Upgrade
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify roles preserved
        assertEq(proxy.hasRole(proxy.MINTER_ROLE(), minter), true);
        assertEq(proxy.hasRole(proxy.TRANSFER_AGENT_ROLE(), agent), true);
    }

    function test_UpgradePreservesSeasonStatus() public {
        // Lock a season before upgrade
        proxy.setSeasonStatus(SEASON, FP1155.SeasonStatus.LOCKED);

        // Upgrade
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify season status preserved
        assertEq(uint256(proxy.seasonStatus(SEASON)), uint256(FP1155.SeasonStatus.LOCKED));
    }

    function test_UpgradePreservesPauseState() public {
        // Pause before upgrade
        proxy.pause();
        assertTrue(proxy.paused());

        // Upgrade
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify still paused
        assertTrue(proxy.paused());

        // Can unpause after upgrade
        proxy.unpause();
        assertFalse(proxy.paused());
    }

    // ============ Functionality After Upgrade Tests ============

    function test_CanMintAfterUpgrade() public {
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Should still be able to mint
        proxy.mint(user, SEASON, 100, "");
        assertEq(proxy.balanceOf(user, SEASON), 100);
    }

    function test_CanGrantRolesAfterUpgrade() public {
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Should still be able to grant roles
        address newMinter = address(0xDEAD);
        proxy.grantRole(proxy.MINTER_ROLE(), newMinter);
        assertTrue(proxy.hasRole(proxy.MINTER_ROLE(), newMinter));
    }

    function test_CanLockSeasonAfterUpgrade() public {
        FP1155 newImplementation = new FP1155();
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Should still be able to lock seasons
        proxy.setSeasonStatus(SEASON, FP1155.SeasonStatus.LOCKED);
        assertEq(uint256(proxy.seasonStatus(SEASON)), uint256(FP1155.SeasonStatus.LOCKED));
    }

    // ============ Multiple Upgrade Tests ============

    function test_MultipleUpgrades() public {
        // Initial state
        proxy.mint(user, SEASON, 100, "");

        // First upgrade
        FP1155 newImpl1 = new FP1155();
        proxy.upgradeToAndCall(address(newImpl1), "");
        assertEq(proxy.balanceOf(user, SEASON), 100);

        // Add more state
        proxy.mint(user, SEASON, 50, "");
        assertEq(proxy.balanceOf(user, SEASON), 150);

        // Second upgrade
        FP1155 newImpl2 = new FP1155();
        proxy.upgradeToAndCall(address(newImpl2), "");
        assertEq(proxy.balanceOf(user, SEASON), 150);

        // Functionality still works
        proxy.mint(user, SEASON, 25, "");
        assertEq(proxy.balanceOf(user, SEASON), 175);
    }

    // ============ Initialization Protection Tests ============

    function test_CannotReinitializeProxy() public {
        // Try to reinitialize - should fail
        vm.expectRevert();
        proxy.initialize("ipfs://new/", admin);
    }

    function test_CannotInitializeImplementationDirectly() public {
        // Implementation should not be initializable after deployment
        FP1155 standalone = new FP1155();
        vm.expectRevert();
        standalone.initialize("ipfs://test/", admin);
    }

    // ============ Edge Cases ============

    function test_UpgradeToSameImplementation() public {
        // Upgrading to the same implementation should work (no-op)
        proxy.upgradeToAndCall(address(implementation), "");
        
        // State should still be intact
        proxy.mint(user, SEASON, 100, "");
        assertEq(proxy.balanceOf(user, SEASON), 100);
    }

    function test_CannotUpgradeToZeroAddress() public {
        vm.expectRevert();
        proxy.upgradeToAndCall(address(0), "");
    }

    function test_UpgradeWithData() public {
        // Upgrade with additional initialization data
        FP1155 newImplementation = new FP1155();
        
        // Use empty data (no additional init needed)
        bytes memory data = "";
        proxy.upgradeToAndCall(address(newImplementation), data);
        
        // State preserved
        proxy.mint(user, SEASON, 100, "");
        assertEq(proxy.balanceOf(user, SEASON), 100);
    }

    // ============ Events ============
    event Upgraded(address indexed implementation);

    // ============ ERC1155Receiver Implementation ============
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
