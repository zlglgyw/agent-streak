# AgentStreak

Daily check-in streaks and soulbound badges for Agent ID holders on BNB Chain.

AgentStreak is a submission for the Binance Agent ID Hackathon (submission period
18 Nov – 9 Dec 2026). It gives AI agents with an Agent ID an on-chain attendance
record: check in once a day, build a streak, and earn soulbound badge NFTs at
streak milestones (3 / 7 / 14 / 30 days).

- **Free to use** — check-ins and badge claims cost only network gas. No payments,
  no token sale, no promised returns of any kind.
- **Agent ID-gated** — only addresses holding an Agent ID (ERC-721) can check in.
  Holder status is checked on-chain via `balanceOf` on the Agent ID contract.
- **Soulbound badges** — badges are non-transferable NFTs with fully on-chain
  metadata (SVG rendered in the contract, no IPFS dependency).
- **No backend** — the frontend is a static page that talks directly to public
  BSC RPC endpoints. No server stores sessions or credentials. We never ask for
  seed phrases, private keys, or pairing codes.

## Repository layout

```
contracts/   Foundry project: AgentStreak.sol + tests + mock Agent ID (testnet)
web/         Static single-page frontend (no build step)
```

## Deployed contracts

| Network        | AgentStreak | Agent ID (gating) |
|----------------|-------------|-------------------|
| BSC Testnet (97) | _Pending faucet funding — deployer `0x8b87ea0Ac6cF2E907B266081C0E6c18AEACaE77D` awaits tBNB_ | Mock Agent ID (testnet only) |
| BSC Mainnet (56) | _TBD after mainnet deploy (pending approval)_ | `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` |

Local end-to-end test (anvil, 18 Nov 2026): deploy + 3 check-ins + badge
claim all verified. Deploy gas 2,039,548 (≈ 0.00204 BNB ≈ $1.20 at 1 gwei).
See `contracts/README.md` for the full gas table.

## Owner permissions (disclosed)

The contract owner can ONLY:

- `pause()` / `unpause()` — emergency pause of check-ins and badge claims.
- `transferOwnership(address)` — hand ownership to another address.

The owner CANNOT mint badges, change any user's streak or check-in history,
withdraw funds (the contract holds no funds and accepts no payments), freeze
assets, change fees (there are none), or modify badge metadata rules.

## Build & test (contracts)

```bash
cd contracts
export PATH="$HOME/.foundry/bin:$PATH"
RAYON_NUM_THREADS=1 forge build
RAYON_NUM_THREADS=1 forge test -vvv
```

## Run the frontend

```bash
cd web
python3 -m http.server 8000
# open http://localhost:8000
```

Set the deployed contract address in `web/config.js` before use.

## Verify on BscScan

Contract source is verified on BscScan (see `contracts/README.md` for the
verification method used). Flattened source can be produced with:

```bash
cd contracts
RAYON_NUM_THREADS=1 forge flatten src/AgentStreak.sol > AgentStreak.flattened.sol
```

## Hackathon

- Announcement: https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf
- Project uses Agent ID for access control (check-in gating) and identity
  (streaks and badges are bound to the Agent ID holder's address).

## Disclaimer

AgentStreak is a reputation/attendance toy for AI agents. Badges have no
monetary value and no yield. Nothing here is financial advice.
