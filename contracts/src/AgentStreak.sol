// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title AgentStreak
/// @notice Daily check-in streaks for Agent ID holders, rewarded with soulbound
///         on-chain SVG badge NFTs. Check-ins and badge claims are FREE
///         (callers pay only network gas). No payments, no yields, no promises
///         of returns of any kind.
///
/// @dev Agent ID gate: the Agent ID contract address is supplied to the
///      constructor (never hardcoded) so tests can use a mock and deployments
///      can point at the real contract. Mainnet Agent ID (SPACE ID, ERC-721
///      non-transferable): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
///
/// @dev OWNER POWERS — MINIMAL AND EXPLICIT. The owner can ONLY:
///      (a) pause / unpause the contract in an emergency (pausing halts
///          checkIn() and claimBadge(); it never touches user data, streaks,
///          or badges, and it cannot freeze or move anyone's tokens);
///      (b) transferOwnership() to a new owner.
///      The owner CANNOT: mint badges for free, mint for anyone, withdraw
///      funds (the contract never holds funds — all functions are free),
///      set any tax/fee, freeze or seize assets, or modify any user's
///      check-in data or streaks. There are no such functions in this
///      contract, by design.
contract AgentStreak is ERC721, Ownable, Pausable {
    using Strings for uint256;

    // ------------------------------------------------------------------------
    // Types & storage
    // ------------------------------------------------------------------------

    /// @notice Per-user check-in statistics.
    struct UserStats {
        uint256 totalCheckIns;
        uint256 currentStreak;
        uint256 longestStreak;
        /// @notice UTC day number (block.timestamp / 86400) of the last check-in.
        uint256 lastCheckInDay;
    }

    /// @notice The Agent ID ERC-721 contract used as the holder gate.
    IERC721 public immutable agentId;

    /// @notice Valid badge milestones (days of consecutive check-ins).
    uint256[] public milestones = [3, 7, 14, 30];

    mapping(address => UserStats) private _stats;
    mapping(address => mapping(uint256 => bool)) private _badges; // user => milestone => claimed
    mapping(uint256 => uint256) private _tokenMilestone; // tokenId => milestone
    mapping(uint256 => uint256) private _tokenStreak; // tokenId => streak at claim time
    uint256 private _nextTokenId;
    uint256 private _totalCheckInsGlobal;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    event CheckedIn(address indexed user, uint256 day, uint256 streak);
    event BadgeClaimed(address indexed user, uint256 milestone, uint256 tokenId);

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------

    error NotAgentIdHolder(address user);
    error AlreadyCheckedInToday(address user, uint256 day);
    error InvalidMilestone(uint256 milestone);
    error MilestoneNotReached(uint256 milestone, uint256 currentStreak);
    error BadgeAlreadyClaimed(address user, uint256 milestone);
    error SoulboundToken(); // badges cannot be transferred or approved
    error RenounceDisabled(); // ownership renouncement is disabled by design
    error ZeroAddress();

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------

    /// @param agentIdContract Address of the Agent ID ERC-721 contract
    ///        (mainnet: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
    /// @param initialOwner Address that receives the minimal owner powers.
    constructor(address agentIdContract, address initialOwner)
        ERC721("AgentStreak", "ASTREAK")
        Ownable(initialOwner)
    {
        if (agentIdContract == address(0) || initialOwner == address(0)) revert ZeroAddress();
        agentId = IERC721(agentIdContract);
    }

    // ------------------------------------------------------------------------
    // Check-ins
    // ------------------------------------------------------------------------

    /// @notice Check in for today (UTC day). Free — gas only.
    /// @dev Only Agent ID holders (balanceOf > 0). Max once per UTC day.
    ///      Streak +1 if yesterday was checked in, otherwise resets to 1.
    function checkIn() external whenNotPaused {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder(msg.sender);

        uint256 day = _today();
        UserStats storage s = _stats[msg.sender];
        if (s.lastCheckInDay == day) revert AlreadyCheckedInToday(msg.sender, day);

        if (s.totalCheckIns > 0 && s.lastCheckInDay + 1 == day) {
            s.currentStreak += 1;
        } else {
            s.currentStreak = 1; // first check-in, or streak broken
        }
        if (s.currentStreak > s.longestStreak) s.longestStreak = s.currentStreak;
        s.totalCheckIns += 1;
        s.lastCheckInDay = day;
        _totalCheckInsGlobal += 1;

        emit CheckedIn(msg.sender, day, s.currentStreak);
    }

    // ------------------------------------------------------------------------
    // Badges (soulbound ERC-721, on-chain SVG metadata)
    // ------------------------------------------------------------------------

    /// @notice Claim the soulbound badge for a milestone streak. Free — gas only.
    /// @param milestone One of 3, 7, 14, 30. Requires currentStreak >= milestone.
    ///        One badge per milestone per address.
    function claimBadge(uint256 milestone) external whenNotPaused {
        if (!_isValidMilestone(milestone)) revert InvalidMilestone(milestone);
        UserStats storage s = _stats[msg.sender];
        if (s.currentStreak < milestone) {
            revert MilestoneNotReached(milestone, s.currentStreak);
        }
        if (_badges[msg.sender][milestone]) revert BadgeAlreadyClaimed(msg.sender, milestone);

        _badges[msg.sender][milestone] = true;
        uint256 tokenId = ++_nextTokenId;
        _tokenMilestone[tokenId] = milestone;
        _tokenStreak[tokenId] = s.currentStreak;
        _safeMint(msg.sender, tokenId);

        emit BadgeClaimed(msg.sender, milestone, tokenId);
    }

    /// @notice Fully on-chain metadata: base64 JSON with an on-chain SVG image.
    /// @dev No IPFS, no external dependencies. Reverts for nonexistent tokens
    ///      (via _requireOwned, inherited from ERC721 in OZ v5).
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 milestone = _tokenMilestone[tokenId];
        uint256 streak = _tokenStreak[tokenId];

        string memory svg = _buildSvg(milestone, streak);
        string memory json = string(
            abi.encodePacked(
                '{"name":"AgentStreak ',
                milestone.toString(),
                '-Day Badge","description":"Soulbound badge for a ',
                milestone.toString(),
                '-day check-in streak on AgentStreak. Earned free by Agent ID holders.","image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '","attributes":[{"trait_type":"Milestone","value":',
                milestone.toString(),
                '},{"trait_type":"Streak at claim","value":',
                streak.toString(),
                '}]}'
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /// @dev Simple on-chain SVG: dark card, AgentStreak wordmark, milestone and streak.
    function _buildSvg(uint256 milestone, uint256 streak) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">',
                '<rect width="400" height="400" rx="24" fill="#0f172a"/>',
                '<circle cx="200" cy="150" r="90" fill="#f59e0b"/>',
                '<text x="200" y="168" font-family="sans-serif" font-size="56" font-weight="bold" fill="#0f172a" text-anchor="middle">',
                milestone.toString(),
                '</text>',
                '<text x="200" y="280" font-family="sans-serif" font-size="28" font-weight="bold" fill="#f8fafc" text-anchor="middle">AgentStreak</text>',
                '<text x="200" y="316" font-family="sans-serif" font-size="20" fill="#94a3b8" text-anchor="middle">',
                milestone.toString(),
                '-Day Streak Badge</text>',
                '<text x="200" y="348" font-family="sans-serif" font-size="16" fill="#94a3b8" text-anchor="middle">Streak at claim: ',
                streak.toString(),
                '</text>',
                "</svg>"
            )
        );
    }

    // ------------------------------------------------------------------------
    // Soulbound enforcement: badges can never leave their owner.
    // ------------------------------------------------------------------------

    /// @dev Blocks every transfer (minting from address(0) is the only allowed
    ///      movement; burning is not implemented). This covers transferFrom and
    ///      safeTransferFrom, which both route through _update.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert SoulboundToken();
        return super._update(to, tokenId, auth);
    }

    /// @dev Approvals are meaningless for a non-transferable token — reject them.
    function approve(address, uint256) public pure override {
        revert SoulboundToken();
    }

    /// @dev Approvals are meaningless for a non-transferable token — reject them.
    function setApprovalForAll(address, bool) public pure override {
        revert SoulboundToken();
    }

    // ------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------

    /// @notice Full check-in stats for a user.
    function getStats(address user)
        external
        view
        returns (uint256 totalCheckIns, uint256 currentStreak, uint256 longestStreak, uint256 lastCheckInDay)
    {
        UserStats storage s = _stats[user];
        return (s.totalCheckIns, s.currentStreak, s.longestStreak, s.lastCheckInDay);
    }

    /// @notice True if `user` has already claimed the badge for `milestone`.
    function hasBadge(address user, uint256 milestone) external view returns (bool) {
        return _badges[user][milestone];
    }

    /// @notice True if `user` is an Agent ID holder and has not checked in today.
    function canCheckInToday(address user) external view returns (bool) {
        return agentId.balanceOf(user) > 0 && _stats[user].lastCheckInDay != _today();
    }

    /// @notice Total check-ins across all users.
    function totalCheckInsGlobal() external view returns (uint256) {
        return _totalCheckInsGlobal;
    }

    /// @notice Milestone (3/7/14/30) a badge token was claimed for.
    function tokenMilestone(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenMilestone[tokenId];
    }

    // ------------------------------------------------------------------------
    // Owner powers (MINIMAL — see contract-level docs above)
    // ------------------------------------------------------------------------

    /// @notice Emergency pause: halts checkIn() and claimBadge(). Owner only.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume after an emergency pause. Owner only.
    function unpause() external onlyOwner {
        _unpause();
    }

    // transferOwnership() is inherited from OpenZeppelin Ownable (owner only).

    /// @dev Ownership renouncement is disabled on purpose: renouncing would
    ///      permanently remove the emergency pause, so the owner powers stay
    ///      exactly (a) pause/unpause and (b) transferOwnership — nothing else.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    // ------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------

    /// @notice Current UTC day number.
    function _today() internal view returns (uint256) {
        return block.timestamp / 86400;
    }

    function _isValidMilestone(uint256 milestone) internal view returns (bool) {
        uint256 len = milestones.length;
        for (uint256 i; i < len; ++i) {
            if (milestones[i] == milestone) return true;
        }
        return false;
    }
}
