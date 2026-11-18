// AgentStreak configuration.
// Fill in agentStreakAddress after the contract is deployed.
// Everything else is safe to change without touching app.js.

const CONFIG = {
  // AgentStreak contract address. Placeholder until deployed.
  // Mainnet (chainId 56) and testnet (chainId 97) use the same field:
  // set the address for whichever network you deploy to, and update
  // `activeChain` below to match.
  agentStreakAddress: "0xbD6bFED52a9feCC101F4829FB239302c46D081ED",

  // AgentStreak contract address on testnet (chainId 97). Placeholder until deployed.
  agentStreakAddressTestnet: "0x0000000000000000000000000000000000000000",

  // Agent ID (ERC-721) on BNB Chain mainnet.
  agentIdAddress: "0x60b9262456de011f7d15a54cdd8c48baaa8b022f",

  // Mock Agent ID on testnet (filled after testnet deploy).
  agentIdAddressTestnet: "0x0000000000000000000000000000000000000000",

  // Default network: 56 = BNB Chain mainnet, 97 = BNB Chain testnet.
  chainId: 56,
  chainIdTestnet: 97,

  // Public read-only RPC endpoints (no API key needed).
  rpcMainnet: "https://bsc-dataseed.binance.org/",
  rpcTestnet: "https://data-seed-prebsc-1-s1.bnbchain.org:8545/",

  // Badge milestones (days of streak required).
  milestones: [3, 7, 14, 30],

  // How far back the "Recent check-ins" feed looks (blocks).
  feedBlockRange: 1000,

  // Block the AgentStreak contract was deployed at (0 = unknown).
  // Set this after deploy so the feed can scan from deployment.
  deployBlock: 134317047,

  // Block explorers.
  explorerMainnet: "https://bscscan.com",
  explorerTestnet: "https://testnet.bscscan.com",

  // Links shown in the footer.
  repoUrl: "https://github.com/zlglgyw/agent-streak",
};
