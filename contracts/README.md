# AgentStreak — Smart Contracts

Daily check-in streaks for Agent ID holders, rewarded with soulbound
on-chain SVG badge NFTs. Built for the Binance Agent ID Hackathon.

- **Contract:** `AgentStreak` (ERC-721, symbol `ASTREAK`)
- **Check-ins and badge claims are FREE** — callers pay only network gas.
  No payments, no yields, no promises of returns.
- **Agent ID gate:** only addresses holding at least 1 Agent ID NFT
  (`balanceOf > 0` on the Agent ID contract) can check in.
- **Milestones:** 3 / 7 / 14 / 30 consecutive days. One soulbound badge
  per milestone per address. Badges are non-transferable
  (`transferFrom` / `safeTransferFrom` / `approve` / `setApprovalForAll`
  all revert).
- **Metadata:** fully on-chain — `tokenURI` returns
  `data:application/json;base64` with an embedded on-chain SVG image.
  No IPFS, no external dependencies.

## Agent ID contract addresses

- **Mainnet Agent ID (SPACE ID, ERC-721 non-transferable):**
  `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`
- The Agent ID address is a **constructor argument, never hardcoded** —
  tests use a mock (`MockAgentId` in `test/AgentStreak.t.sol`).

## Owner powers (minimal, explicit)

The owner can ONLY:

1. **Emergency pause / unpause** — halts `checkIn()` and `claimBadge()`.
   It never touches user data, streaks, or badges, and cannot freeze or
   move anyone's tokens.
2. **`transferOwnership()`** — hand the above powers to a new owner.

The owner CANNOT mint badges, mint for anyone, withdraw funds (the
contract never holds funds), set any tax/fee, freeze or seize assets,
or modify any user's check-in data or streaks. No such functions exist
in the contract, by design. `renounceOwnership()` (inherited from
OpenZeppelin Ownable) is overridden to always revert, so the emergency
pause can never be accidentally bricked — the owner powers are exactly
the two listed above, nothing else. See the contract-level comments in
`src/AgentStreak.sol`.

## Build & test

Foundry is required (`~/.foundry/bin` in this workspace).

```bash
export PATH="$HOME/.foundry/bin:$PATH"
# IMPORTANT: every forge command MUST run with RAYON_NUM_THREADS=1 —
# this sandbox rejects parallel write() calls with EPERM. If a build or
# test fails with EPERM, just retry the same command.
RAYON_NUM_THREADS=1 forge build
RAYON_NUM_THREADS=1 forge test -vvv
```

Dependencies: OpenZeppelin Contracts v5.0.2 + forge-std (git submodules
under `lib/`; install with `forge install` if missing).

## ABI

After a build, the ABI lives in:

```
out/AgentStreak.sol/AgentStreak.json
```

## Deploy

Deploy script: `script/Deploy.s.sol`. It reads env vars:

- `PRIVATE_KEY` (required) — deployer key. Never commit it.
- `AGENT_ID` (optional) — Agent ID contract address.
  Mainnet: `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`.
  Unset: deploys the testnet-only `MockAgentId` first and mints one mock
  Agent ID to the deployer (testnet/local only — never on mainnet).
- `OWNER` (optional) — owner address; defaults to the deployer.

```bash
export PATH="$HOME/.foundry/bin:$PATH"
PRIVATE_KEY=<key> RAYON_NUM_THREADS=1 forge script script/Deploy.s.sol \
  --rpc-url https://data-seed-prebsc-1-s1.bnbchain.org:8545 --broadcast
```

**Mainnet deploy requires explicit approval** — it spends real BNB (see
cost estimate below). Never deploy to mainnet from this folder casually.

### Gas measured (local anvil e2e, 18 Nov 2026)

| Operation | Gas |
|---|---|
| AgentStreak deploy | 2,039,548 |
| MockAgentId deploy (testnet only) | 957,408 |
| checkIn (first) | 142,161 |
| checkIn (repeat) | 56,962 |
| claimBadge | 168,654 |

Mainnet cost estimate at 1 gwei (BNB ~$589): deploy ≈ 0.00204 BNB ≈ $1.20.
At the live reported gas price (0.05 gwei, 18 Nov 2026) it would be ≈ $0.06,
but validator minimums may require more — budget $1.20. End-to-end verified
on anvil: 3 check-ins across 3 days, streak 3, badge claimed, tokenURI
decodes to "AgentStreak 3-Day Badge", transfer + double-claim + non-holder
check-in all revert as designed.

### BscScan verification

No API key is available in this environment, so verify via the BscScan web
UI with flattened source:

```bash
RAYON_NUM_THREADS=1 forge flatten src/AgentStreak.sol > AgentStreak.flattened.sol
```

Then verify at bscscan.com (or testnet.bscscan.com) with compiler 0.8.20,
optimizer enabled, 200 runs.
