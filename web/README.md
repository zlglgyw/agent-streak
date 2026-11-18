# AgentStreak — Frontend

Static single-page app. No build step, no backend, no framework. Vanilla JS +
ethers.js v6 (loaded from CDN) talking to a public BSC RPC and the user's
injected wallet provider (Binance Wallet, MetaMask, …).

## Run locally

```bash
cd web
python3 -m http.server 8000
# open http://localhost:8000
```

Any static file server works. The page must be served over HTTP(S) — opening
`index.html` directly from disk may block the CDN script / RPC calls.

## Configure the contract address

Edit `config.js`:

- `agentStreakAddress` — deployed AgentStreak contract (mainnet, chain 56).
- `agentStreakAddressTestnet` — deployed contract on BSC Testnet (chain 97).
- `agentIdAddressTestnet` — mock Agent ID contract on testnet (mainnet field
  already points at the real Agent ID contract
  `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`).
- `deployBlock` — block number the contract was deployed at, so the
  "Recent check-ins" feed scans from deployment instead of the last
  `feedBlockRange` blocks.
- `rpcMainnet` / `rpcTestnet` — change if the public endpoints are rate-limited.

Until the addresses are set, the page shows a "Contract not deployed yet"
banner and check-in stays disabled. The feed also stays empty.

## Features

- Connect wallet (injected provider) + switch/add BSC mainnet & testnet.
- Agent ID holder check (`balanceOf > 0` on the Agent ID contract).
- Check-in button (1x per UTC day), live streak stats.
- Soulbound badge cards for milestones 3 / 7 / 14 / 30 with claim buttons.
- Recent check-ins feed from `CheckedIn` events via public RPC (works
  without a connected wallet).
- No seed phrase / private key is ever requested. No returns are promised.

## Files

- `index.html` — page structure.
- `app.js` — wallet, contract calls, feed.
- `config.js` — addresses, RPCs, milestones.
- `style.css` — dark theme, mobile-friendly.
