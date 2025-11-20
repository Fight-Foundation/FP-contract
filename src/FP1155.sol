// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {
    ERC1155PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import {
    ERC1155BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title FP (Fighting Points) ERC-1155 on BSC
 * @notice Seasonal, non-tradable reputation asset. Transfers are restricted to an allowlist.
 *         Each season is a tokenId. Seasons can be LOCKED at end, prohibiting new mint/transfer but allowing burns.
 */
contract FP1155 is
    Initializable,
    UUPSUpgradeable,
    ERC1155Upgradeable,
    ERC1155PausableUpgradeable,
    ERC1155BurnableUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ Roles ============
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TRANSFER_AGENT_ROLE = keccak256("TRANSFER_AGENT_ROLE");
    bytes32 public constant SEASON_ADMIN_ROLE = keccak256("SEASON_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CLAIM_SIGNER_ROLE = keccak256("CLAIM_SIGNER_ROLE");

    // ============ Types ============
    enum SeasonStatus {
        OPEN, // 0
        LOCKED // 1
    }

    // ============ Storage ============
    // Optional base URI is handled by ERC1155
    mapping(uint256 => SeasonStatus) private _seasonStatus; // default 0 (OPEN)
    mapping(address => bool) private _allowlist;
    mapping(address => uint256) public nonces; // per-user monotonically increasing nonce

    // EIP-712 typehash for claim typed struct
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(address account,uint256 seasonId,uint256 amount,uint256 nonce,uint256 deadline)");

    // ============ Events ============
    event SeasonStatusUpdated(uint256 indexed seasonId, SeasonStatus status);
    event AllowlistUpdated(address indexed account, bool allowed);
    event ClaimProcessed(address indexed account, uint256 indexed seasonId, uint256 amount, uint256 nonce);

    // ============ Initializer ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory baseURI, address admin) public initializer {
        require(admin != address(0), "admin=0");
        __ERC1155_init(baseURI);
        __EIP712_init("FP1155", "1");
        __ERC1155Pausable_init();
        __ERC1155Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(SEASON_ADMIN_ROLE, admin);
        // Admin can manage claim signers via role admin
    }

    /// @dev UUPS upgrade authorization: only DEFAULT_ADMIN_ROLE can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    // ============ Admin Ops ============
    function setURI(string memory newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newBaseURI);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setTransferAllowlist(address account, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _allowlist[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    function setSeasonStatus(uint256 seasonId, SeasonStatus status) external onlyRole(SEASON_ADMIN_ROLE) {
        // Irreversible lock: cannot move from LOCKED to OPEN
        SeasonStatus current = _seasonStatus[seasonId];
        if (current == SeasonStatus.LOCKED) {
            require(status == SeasonStatus.LOCKED, "locked: irreversible");
        }
        _seasonStatus[seasonId] = status;
        emit SeasonStatusUpdated(seasonId, status);
    }

    // ============ Views ============
    function seasonStatus(uint256 seasonId) external view returns (SeasonStatus) {
        return _seasonStatus[seasonId];
    }

    function isOnAllowlist(address account) public view returns (bool) {
        return _allowlist[account];
    }

    function endpointAllowed(address account) public view returns (bool) {
        return _allowlist[account] || hasRole(TRANSFER_AGENT_ROLE, account);
    }

    function isTransfersAllowed(address from, address to, uint256 seasonId) public view returns (bool) {
        if (from == address(0)) {
            // mint: season must be OPEN
            return _seasonStatus[seasonId] == SeasonStatus.OPEN;
        }
        if (to == address(0)) {
            // burn: always allowed (even LOCKED)
            return true;
        }
        // regular transfer: season must be OPEN
        if (_seasonStatus[seasonId] != SeasonStatus.OPEN) {
            return false;
        }
        // If destination has TRANSFER_AGENT_ROLE, only destination needs to be allowed
        // Otherwise, both endpoints must be allowed
        if (hasRole(TRANSFER_AGENT_ROLE, to)) {
            return endpointAllowed(to);
        }
        return endpointAllowed(from) && endpointAllowed(to);
    }

    // ============ Mint API ============
    function mint(address to, uint256 seasonId, uint256 amount, bytes memory data)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        require(to != address(0), "mint: to=0");
        require(amount > 0, "amount=0");
        _mint(to, seasonId, amount, data);
    }

    function mintBatch(address to, uint256[] memory seasonIds, uint256[] memory amounts, bytes memory data)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        require(seasonIds.length > 0, "mintBatch: empty arrays");
        require(seasonIds.length == amounts.length, "mintBatch: length mismatch");
        // Disallow zero amounts to avoid no-op writes
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "amount=0");
        }
        _mintBatch(to, seasonIds, amounts, data);
    }

    // ============ Claims (server-signed) ============
    /**
     * @notice Claim FP for the caller using a server signature (user pays gas).
     * @param seasonId token id (season)
     * @param amount amount to mint
     * @param deadline unix timestamp after which claim is invalid
     * @param signature EIP-712 signature from an address with CLAIM_SIGNER_ROLE over Claim struct
     */
    function claim(uint256 seasonId, uint256 amount, uint256 deadline, bytes calldata signature)
        external
        whenNotPaused
        nonReentrant
    {
        require(block.timestamp <= deadline, "claim: expired");
        require(amount > 0, "amount=0");
        require(_seasonStatus[seasonId] == SeasonStatus.OPEN, "claim: season locked");

        uint256 nonce = nonces[msg.sender];
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, seasonId, amount, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        require(hasRole(CLAIM_SIGNER_ROLE, signer), "claim: invalid signer");

        // increment nonce before effects to prevent reentrancy in any hooks
        nonces[msg.sender] = nonce + 1;
        emit ClaimProcessed(msg.sender, seasonId, amount, nonce);
        _mint(msg.sender, seasonId, amount, "");
    }

    // ============ Agent-assisted transfers =========
    /**
     * @notice Transfer tokens between addresses by an agent without prior user approval.
     * @dev Caller must hold TRANSFER_AGENT_ROLE. Normal transfer guards still apply:
     *      - Season must be OPEN
     *      - Both endpoints must be allowed via allowlist or TRANSFER_AGENT_ROLE
     *      Reverts with the same errors as a normal transfer if conditions fail.
     */
    function agentTransferFrom(address from, address to, uint256 seasonId, uint256 amount, bytes calldata data)
        external
        whenNotPaused
        onlyRole(TRANSFER_AGENT_ROLE)
        nonReentrant
    {
        require(from != address(0), "agentTransferFrom: from=0");
        require(to != address(0), "agentTransferFrom: to=0");
        require(amount > 0, "amount=0");
        // Bypass external approval requirement by calling internal transfer
        _safeTransferFrom(from, to, seasonId, amount, data);
    }

    // Expose current EIP-712 domain separator for client-side signing in tests/integration
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ============ Transfer Guard ============
    // OZ v5.1 uses _update as the transfer/mint/burn hook.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155PausableUpgradeable)
    {
        // Enforce season + allowlist rules per token id
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 id = ids[i];
            if (from == address(0)) {
                // Mint: only allowed if season OPEN
                require(_seasonStatus[id] == SeasonStatus.OPEN, "mint: season locked");
            } else if (to == address(0)) {
                // Burn: always allowed
            } else {
                // Transfer between addresses
                require(_seasonStatus[id] == SeasonStatus.OPEN, "transfer: season locked");
                // If destination has TRANSFER_AGENT_ROLE (e.g., Booster contract), allow transfer from any user
                // Otherwise, both endpoints must be allowed
                if (!hasRole(TRANSFER_AGENT_ROLE, to)) {
                    require(endpointAllowed(from) && endpointAllowed(to), "transfer: endpoints not allowed");
                }
            }
        }
        super._update(from, to, ids, values);
    }

    // ============ Interface Support ============
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
