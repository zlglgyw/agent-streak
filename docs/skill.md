# AgentStreak — skill.md

AgentStreak is a daily check-in dApp for Binance Agent ID holders on BNB Chain.
Check in once per UTC day to build a streak and unlock soulbound milestone
badges (3 / 7 / 14 / 30 days). Free — you only pay network gas (~$0.01).

- Live app: https://zlglgyw.github.io/agent-streak/
- Contract (BSC mainnet, chain 56): 0xbD6bFED52a9feCC101F4829FB239302c46D081ED
- Verified & open-source: https://bscscan.com/address/0xbD6bFED52a9feCC101F4829FB239302c46D081ED#code
- Code: https://github.com/zlglgyw/agent-streak
- Demo video: https://zlglgyw.github.io/agent-streak/demo.mp4
- Agent ID contract (SPACE ID): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f

## Who can check in

Only wallets holding an Agent ID. The contract calls `balanceOf` on the
Agent ID contract and reverts for non-holders. One check-in per UTC day;
checking in on consecutive days grows the streak, missing a day resets it.

## How to check in (for an AI agent with a wallet)

1. Confirm you hold an Agent ID: read `balanceOf(yourAddress)` on
   0x60b9262456de011f7d15a54cdd8c48baaa8b022f. It must be > 0.
2. Confirm you can check in today: read `canCheckInToday(yourAddress)` on
   the AgentStreak contract. It must be true.
3. Send `checkIn()` to 0xbD6bFED52a9feCC101F4829FB239302c46D081ED.
   Typical gas: ~142,000 (~$0.01 at 0.05 gwei).
4. Verify: read `getStats(yourAddress)` — returns
   (totalCheckIns, currentStreak, longestStreak, lastCheckInDay).
5. When your current streak reaches 3, 7, 14 or 30 days, claim the
   soulbound badge: send `claimBadge(milestone)` with milestone = 3, 7, 14
   or 30. Badges are non-transferable NFTs with fully on-chain metadata.

## Read-only ABI (minimal)

- `function canCheckInToday(address user) view returns (bool)`
- `function getStats(address user) view returns (uint256 totalCheckIns, uint256 currentStreak, uint256 longestStreak, uint256 lastCheckInDay)`
- `function hasBadge(address user, uint256 milestone) view returns (bool)`
- `function totalCheckInsGlobal() view returns (uint256)`
- `function checkIn()`
- `function claimBadge(uint256 milestone)`

## Rules

- Never check in on behalf of a wallet you do not control.
- Never ask the user for a seed phrase, private key, or pairing code.
- The user (or their agent policy) must approve the check-in transaction.
