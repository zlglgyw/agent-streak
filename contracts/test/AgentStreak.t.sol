// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AgentStreak} from "../src/AgentStreak.sol";

/// @notice Minimal mock of the Agent ID ERC-721 (non-transferable in reality;
///         transferability is irrelevant here — only balanceOf matters).
contract MockAgentId is ERC721 {
    uint256 private _nextId;

    constructor() ERC721("Mock Agent ID", "MOCKID") {}

    function mint(address to) external returns (uint256) {
        uint256 id = ++_nextId;
        _mint(to, id);
        return id;
    }
}

contract AgentStreakTest is Test {
    AgentStreak public streak;
    MockAgentId public agentId;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice"); // Agent ID holder
    address public bob = makeAddr("bob"); // NOT a holder
    address public carol = makeAddr("carol"); // holder, used for multi-user checks

    // Realistic starting timestamp: 2026-11-18 00:00:00 UTC.
    uint256 constant START = 1794969600;

    function setUp() public {
        vm.warp(START);
        agentId = new MockAgentId();
        streak = new AgentStreak(address(agentId), owner);
        agentId.mint(alice);
        agentId.mint(carol);
    }

    // ------------------------------------------------------------------------
    // (1) Non-holder cannot check in
    // ------------------------------------------------------------------------

    function test_RevertWhen_NotAgentIdHolder_CheckIn() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.NotAgentIdHolder.selector, bob));
        streak.checkIn();
    }

    // ------------------------------------------------------------------------
    // (2) Holder check-in succeeds, streak = 1
    // ------------------------------------------------------------------------

    function test_CheckIn_Success_Streak1() public {
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 current, uint256 longest, uint256 lastDay) = streak.getStats(alice);
        assertEq(total, 1);
        assertEq(current, 1);
        assertEq(longest, 1);
        assertEq(lastDay, START / 86400);
        assertEq(streak.totalCheckInsGlobal(), 1);
        assertFalse(streak.canCheckInToday(alice));
    }

    // ------------------------------------------------------------------------
    // (3) Second check-in on the same day reverts
    // ------------------------------------------------------------------------

    function test_RevertWhen_CheckInTwiceSameDay() public {
        vm.prank(alice);
        streak.checkIn();

        vm.warp(START + 12 hours); // same UTC day
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentStreak.AlreadyCheckedInToday.selector, alice, START / 86400
            )
        );
        streak.checkIn();
    }

    // ------------------------------------------------------------------------
    // (4) Next-day check-in: streak = 2
    // ------------------------------------------------------------------------

    function test_CheckIn_NextDay_Streak2() public {
        vm.prank(alice);
        streak.checkIn();

        vm.warp(START + 1 days);
        assertTrue(streak.canCheckInToday(alice));
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 current, uint256 longest,) = streak.getStats(alice);
        assertEq(total, 2);
        assertEq(current, 2);
        assertEq(longest, 2);
    }

    // ------------------------------------------------------------------------
    // (5) Skip one day: streak resets to 1, longestStreak kept
    // ------------------------------------------------------------------------

    function test_CheckIn_SkipDay_StreakResets_LongestKept() public {
        // 3 consecutive days -> streak 3.
        for (uint256 i; i < 3; ++i) {
            vm.warp(START + i * 1 days);
            vm.prank(alice);
            streak.checkIn();
        }
        (, uint256 current, uint256 longest,) = streak.getStats(alice);
        assertEq(current, 3);
        assertEq(longest, 3);

        // Skip day 4 entirely, check in on day 5.
        vm.warp(START + 4 days);
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 currentAfter, uint256 longestAfter,) = streak.getStats(alice);
        assertEq(total, 4);
        assertEq(currentAfter, 1);
        assertEq(longestAfter, 3);
    }

    // ------------------------------------------------------------------------
    // (6) claimBadge before milestone reverts
    // ------------------------------------------------------------------------

    function test_RevertWhen_ClaimBadgeBeforeMilestone() public {
        vm.prank(alice);
        streak.checkIn(); // streak 1 < 3

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentStreak.MilestoneNotReached.selector, 3, 1)
        );
        streak.claimBadge(3);
    }

    function test_RevertWhen_ClaimBadgeInvalidMilestone() public {
        _checkInDays(alice, 3); // streak 3
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.InvalidMilestone.selector, 5));
        streak.claimBadge(5);
    }

    // ------------------------------------------------------------------------
    // (7) claimBadge at milestone succeeds; token owned; tokenURI valid
    // ------------------------------------------------------------------------

    function test_ClaimBadge_AtMilestone_Success_TokenURI() public {
        _checkInDays(alice, 7); // streak 7

        vm.prank(alice);
        streak.claimBadge(7);

        assertEq(streak.ownerOf(1), alice);
        assertEq(streak.balanceOf(alice), 1);
        assertTrue(streak.hasBadge(alice, 7));
        assertEq(streak.tokenMilestone(1), 7);

        string memory uri = streak.tokenURI(1);
        // Prefix check.
        assertTrue(_startsWith(uri, "data:application/json;base64,"));

        // Decode the base64 JSON and verify it names the milestone and embeds SVG.
        string memory json = _decodeBase64(_stripPrefix(uri, "data:application/json;base64,"));
        assertTrue(_contains(json, '"name":"AgentStreak 7-Day Badge"'));
        assertTrue(_contains(json, "data:image/svg+xml;base64,"));

        // Decode the embedded SVG and verify its contents.
        string memory svgB64 = _extractSvgB64(json);
        string memory svg = _decodeBase64(svgB64);
        assertTrue(_contains(svg, "<svg"));
        assertTrue(_contains(svg, "AgentStreak"));
        assertTrue(_contains(svg, "7-Day Streak Badge"));
        assertTrue(_contains(svg, "Streak at claim: 7"));
    }

    // ------------------------------------------------------------------------
    // (8) Claiming the same milestone twice reverts
    // ------------------------------------------------------------------------

    function test_RevertWhen_ClaimSameMilestoneTwice() public {
        _checkInDays(alice, 3);
        vm.prank(alice);
        streak.claimBadge(3);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentStreak.BadgeAlreadyClaimed.selector, alice, 3)
        );
        streak.claimBadge(3);
    }

    // ------------------------------------------------------------------------
    // (9) Badges are soulbound: transfers and approvals revert
    // ------------------------------------------------------------------------

    function test_RevertWhen_TransferBadge() public {
        _checkInDays(alice, 3);
        vm.prank(alice);
        streak.claimBadge(3);

        vm.prank(alice);
        vm.expectRevert(AgentStreak.SoulboundToken.selector);
        streak.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(AgentStreak.SoulboundToken.selector);
        streak.safeTransferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(AgentStreak.SoulboundToken.selector);
        streak.approve(bob, 1);

        vm.prank(alice);
        vm.expectRevert(AgentStreak.SoulboundToken.selector);
        streak.setApprovalForAll(bob, true);

        // Badge still owned by alice.
        assertEq(streak.ownerOf(1), alice);
    }

    // ------------------------------------------------------------------------
    // (10) Pause blocks checkIn/claimBadge; unpause restores
    // ------------------------------------------------------------------------

    function test_Pause_BlocksCheckInAndClaim_UnpauseRestores() public {
        _checkInDays(alice, 3); // streak 3, badge claimable

        vm.prank(owner);
        streak.pause();
        assertTrue(streak.paused());

        vm.warp(START + 3 days);
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        streak.checkIn();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        streak.claimBadge(3);

        vm.prank(owner);
        streak.unpause();
        assertFalse(streak.paused());

        vm.prank(alice);
        streak.checkIn(); // works again (streak continues: day 3 is consecutive)
        (, uint256 current,,) = streak.getStats(alice);
        assertEq(current, 4);

        vm.prank(alice);
        streak.claimBadge(3);
        assertEq(streak.ownerOf(1), alice);
    }

    // ------------------------------------------------------------------------
    // (11) Only owner can pause / unpause / transferOwnership
    // ------------------------------------------------------------------------

    function test_OnlyOwner_PauseUnpauseTransferOwnership() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        streak.pause();

        vm.prank(owner);
        streak.pause();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        streak.unpause();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        streak.transferOwnership(bob);

        // Owner can transfer; new owner gains the powers, old owner loses them.
        vm.prank(owner);
        streak.unpause();
        vm.prank(owner);
        streak.transferOwnership(bob);
        assertEq(streak.owner(), bob);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner)
        );
        streak.pause();

        vm.prank(bob);
        streak.pause();
        assertTrue(streak.paused());
    }

    function test_RevertWhen_RenounceOwnership() public {
        vm.prank(owner);
        vm.expectRevert(AgentStreak.RenounceDisabled.selector);
        streak.renounceOwnership();
    }

    // ------------------------------------------------------------------------
    // Extra: views, global counter, multiple users, all milestones
    // ------------------------------------------------------------------------

    function test_Views_AndGlobalCounter() public {
        assertFalse(streak.canCheckInToday(bob)); // not a holder
        assertTrue(streak.canCheckInToday(alice));
        assertFalse(streak.hasBadge(alice, 3));

        vm.prank(alice);
        streak.checkIn();
        vm.prank(carol);
        streak.checkIn();
        assertEq(streak.totalCheckInsGlobal(), 2);
    }

    function test_AllMilestonesClaimable() public {
        _checkInDays(alice, 30); // streak 30
        vm.startPrank(alice);
        streak.claimBadge(3);
        streak.claimBadge(7);
        streak.claimBadge(14);
        streak.claimBadge(30);
        vm.stopPrank();

        assertEq(streak.balanceOf(alice), 4);
        assertTrue(streak.hasBadge(alice, 3));
        assertTrue(streak.hasBadge(alice, 7));
        assertTrue(streak.hasBadge(alice, 14));
        assertTrue(streak.hasBadge(alice, 30));
        assertEq(streak.ownerOf(4), alice);
        assertEq(streak.tokenMilestone(4), 30);
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    /// @dev Check in `numDays` consecutive days starting at START, as `user`.
    function _checkInDays(address user, uint256 numDays) internal {
        for (uint256 i; i < numDays; ++i) {
            vm.warp(START + i * 1 days);
            vm.prank(user);
            streak.checkIn();
        }
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (a.length < b.length) return false;
        for (uint256 i; i < b.length; ++i) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _stripPrefix(string memory s, string memory prefix)
        internal
        pure
        returns (string memory)
    {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        bytes memory out = new bytes(a.length - b.length);
        for (uint256 i; i < out.length; ++i) {
            out[i] = a[b.length + i];
        }
        return string(out);
    }

    function _contains(string memory s, string memory needle) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(needle);
        if (b.length > a.length) return false;
        for (uint256 i; i <= a.length - b.length; ++i) {
            bool found = true;
            for (uint256 j; j < b.length; ++j) {
                if (a[i + j] != b[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    /// @dev Extract the base64 payload after "data:image/svg+xml;base64," up to
    ///      the closing quote of the image field.
    function _extractSvgB64(string memory json) internal pure returns (string memory) {
        bytes memory a = bytes(json);
        string memory marker = "data:image/svg+xml;base64,";
        bytes memory m = bytes(marker);
        uint256 start = 0;
        for (uint256 i; i <= a.length - m.length; ++i) {
            bool found = true;
            for (uint256 j; j < m.length; ++j) {
                if (a[i + j] != m[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                start = i + m.length;
                break;
            }
        }
        uint256 end = start;
        while (end < a.length && a[end] != bytes1('"')) ++end;
        bytes memory out = new bytes(end - start);
        for (uint256 i; i < out.length; ++i) out[i] = a[start + i];
        return string(out);
    }

    /// @dev Minimal base64 decoder (standard alphabet, with padding).
    function _decodeBase64(string memory data) internal pure returns (string memory) {
        bytes memory b = bytes(data);
        require(b.length % 4 == 0, "bad base64 length");
        uint256 pad = 0;
        if (b.length > 0 && b[b.length - 1] == bytes1("=")) pad++;
        if (b.length > 1 && b[b.length - 2] == bytes1("=")) pad++;
        uint256 outLen = (b.length / 4) * 3 - pad;
        bytes memory out = new bytes(outLen);
        uint256 o = 0;
        for (uint256 i; i < b.length; i += 4) {
            uint256 n = (_b64val(b[i]) << 18) | (_b64val(b[i + 1]) << 12) | (_b64val(b[i + 2]) << 6)
                | _b64val(b[i + 3]);
            if (o < outLen) out[o++] = bytes1(uint8(n >> 16));
            if (o < outLen) out[o++] = bytes1(uint8(n >> 8));
            if (o < outLen) out[o++] = bytes1(uint8(n));
        }
        return string(out);
    }

    function _b64val(bytes1 c) internal pure returns (uint256) {
        bytes1 a = bytes1("A");
        bytes1 z = bytes1("Z");
        bytes1 la = bytes1("a");
        bytes1 lz = bytes1("z");
        bytes1 zero = bytes1("0");
        bytes1 nine = bytes1("9");
        if (c >= a && c <= z) return uint8(c) - uint8(a);
        if (c >= la && c <= lz) return uint8(c) - uint8(la) + 26;
        if (c >= zero && c <= nine) return uint8(c) - uint8(zero) + 52;
        if (c == bytes1("+")) return 62;
        if (c == bytes1("/")) return 63;
        return 0; // '=' padding
    }
}
