// AgentStreak frontend — vanilla JS + ethers.js v6 (loaded from CDN in index.html).
// No backend. Reads go to a public BSC RPC; writes go through the user's wallet.

const ZERO = "0x0000000000000000000000000000000000000000";

const STREAK_ABI = [
  "function checkIn()",
  "function claimBadge(uint256 milestone)",
  "function getStats(address user) view returns (uint256 totalCheckIns, uint256 currentStreak, uint256 longestStreak, uint256 lastCheckInDay)",
  "function hasBadge(address user, uint256 milestone) view returns (bool)",
  "function canCheckInToday(address user) view returns (bool)",
  "function totalCheckInsGlobal() view returns (uint256)",
  "event CheckedIn(address indexed user, uint256 day, uint256 streak)",
  "event BadgeClaimed(address indexed user, uint256 milestone, uint256 tokenId)",
];
const ERC721_ABI = ["function balanceOf(address owner) view returns (uint256)"];

const $ = (id) => document.getElementById(id);
const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const dayToDate = (d) => (Number(d) === 0 ? "—" : new Date(Number(d) * 86400 * 1000).toISOString().slice(0, 10));

let provider = null;      // BrowserProvider (wallet)
let readProvider = null;  // JsonRpcProvider (public RPC, no wallet needed)
let signer = null;
let account = null;
let chainId = null;

function isTestnet() { return chainId === CONFIG.chainIdTestnet; }
function streakAddress() {
  return isTestnet() ? CONFIG.agentStreakAddressTestnet : CONFIG.agentStreakAddress;
}
function agentIdAddress() {
  return isTestnet() ? CONFIG.agentIdAddressTestnet : CONFIG.agentIdAddress;
}
function explorer() { return isTestnet() ? CONFIG.explorerTestnet : CONFIG.explorerMainnet; }
function rpcUrl() { return isTestnet() ? CONFIG.rpcTestnet : CONFIG.rpcMainnet; }
function deployed() { return streakAddress() && streakAddress() !== ZERO; }

function readContract() {
  return new ethers.Contract(streakAddress(), STREAK_ABI, readProvider);
}
function writeContract() {
  return new ethers.Contract(streakAddress(), STREAK_ABI, signer);
}

function setStatus(msg, isError) {
  const el = $("checkInStatus");
  el.textContent = msg;
  el.style.color = isError ? "#dc2626" : "";
}

async function refreshAll() {
  if (!account) return;
  await refreshHolder();
  await refreshStats();
  await refreshBadges();
}

async function refreshHolder() {
  const el = $("holderStatus");
  if (!deployed()) {
    el.textContent = "Contract not deployed yet — holder check unavailable.";
    return;
  }
  try {
    const agentId = new ethers.Contract(agentIdAddress(), ERC721_ABI, readProvider);
    const bal = await agentId.balanceOf(account);
    if (bal > 0n) {
      el.innerHTML = "Agent ID holder ✓ — you can check in.";
      el.style.color = "#15803d";
    } else {
      el.textContent = "Not an Agent ID holder — check-in requires an Agent ID.";
      el.style.color = "#b45309";
    }
  } catch (e) {
    el.textContent = "Could not check Agent ID status (RPC error). Try again later.";
    el.style.color = "#dc2626";
  }
}

async function refreshStats() {
  const btn = $("checkInBtn");
  if (!deployed()) { btn.disabled = true; return; }
  try {
    const c = readContract();
    const [total, current, longest, last] = await c.getStats(account);
    $("statCurrent").textContent = current.toString();
    $("statLongest").textContent = longest.toString();
    $("statTotal").textContent = total.toString();
    $("statLast").textContent = dayToDate(last);
    const can = await c.canCheckInToday(account);
    if (can) {
      btn.disabled = false;
      btn.textContent = "Check In Today";
      setStatus("");
    } else {
      btn.disabled = true;
      const agentId = new ethers.Contract(agentIdAddress(), ERC721_ABI, readProvider);
      const bal = await agentId.balanceOf(account);
      btn.textContent = bal > 0n ? "Checked in today ✓" : "Check In Today";
      if (bal === 0n) setStatus("Check-in requires an Agent ID.");
    }
  } catch (e) {
    setStatus("Could not load stats (RPC error).", true);
  }
}

async function refreshBadges() {
  const grid = $("badgeGrid");
  grid.innerHTML = "";
  for (const m of CONFIG.milestones) {
    const card = document.createElement("div");
    card.className = "badge";
    card.innerHTML = `<div class="badge-days">${m}</div><div class="badge-label">${m}-Day Streak</div><div class="badge-state muted">…</div>`;
    grid.appendChild(card);
    if (!deployed() || !account) {
      card.querySelector(".badge-state").textContent = "Connect wallet";
      continue;
    }
    try {
      const c = readContract();
      const owned = await c.hasBadge(account, m);
      const [, current] = await c.getStats(account);
      const state = card.querySelector(".badge-state");
      if (owned) {
        card.classList.add("owned");
        state.textContent = "Owned ✓";
      } else if (current >= BigInt(m)) {
        const b = document.createElement("button");
        b.className = "btn small primary";
        b.textContent = "Claim";
        b.onclick = () => claimBadge(m);
        state.textContent = "";
        state.appendChild(b);
      } else {
        state.textContent = `Locked — needs ${m}-day streak`;
      }
    } catch (e) {
      card.querySelector(".badge-state").textContent = "Unavailable";
    }
  }
}

async function loadFeed() {
  const list = $("feedList");
  const note = $("feedNote");
  list.innerHTML = "";
  if (!deployed()) {
    note.textContent = "Feed unavailable — contract not deployed yet.";
    return;
  }
  try {
    const c = readContract();
    const latest = await readProvider.getBlockNumber();
    const from = CONFIG.deployBlock > 0
      ? CONFIG.deployBlock
      : Math.max(0, latest - (CONFIG.feedBlockRange || 1000));
    const events = await c.queryFilter(c.filters.CheckedIn(), from, latest);
    const recent = events.slice(-20).reverse();
    if (recent.length === 0) {
      note.textContent = "No check-ins in the scanned range yet. Be the first!";
      return;
    }
    note.textContent = `Showing ${recent.length} most recent check-in(s).`;
    for (const ev of recent) {
      const li = document.createElement("li");
      const date = dayToDate(ev.args.day);
      li.innerHTML = `<span class="feed-addr">${short(ev.args.user)}</span>
        <span>checked in — streak <b>${ev.args.streak}</b></span>
        <span class="muted">${date}</span>
        <a href="${explorer()}/tx/${ev.transactionHash}" target="_blank" rel="noopener">tx ↗</a>`;
      list.appendChild(li);
    }
  } catch (e) {
    note.textContent = "Could not load the feed (public RPC error). The contract is still usable — try refreshing.";
  }
}

async function doCheckIn() {
  const btn = $("checkInBtn");
  btn.disabled = true;
  setStatus("Waiting for wallet confirmation…");
  try {
    const tx = await writeContract().checkIn();
    setStatus("Transaction sent — waiting for confirmation…");
    await tx.wait();
    setStatus("Checked in! ✓");
    await refreshAll();
    await loadFeed();
  } catch (e) {
    const msg = (e && e.reason) || (e && e.message) || "Transaction failed.";
    setStatus(msg.includes("user rejected") ? "Transaction rejected in wallet." : msg, true);
    btn.disabled = false;
  }
}

async function claimBadge(milestone) {
  setStatus(`Claiming ${milestone}-day badge — confirm in wallet…`);
  try {
    const tx = await writeContract().claimBadge(milestone);
    setStatus("Transaction sent — waiting for confirmation…");
    await tx.wait();
    setStatus(`${milestone}-day badge claimed! ✓`);
    await refreshAll();
  } catch (e) {
    const msg = (e && e.reason) || (e && e.message) || "Claim failed.";
    setStatus(msg.includes("user rejected") ? "Transaction rejected in wallet." : msg, true);
  }
}

async function switchNetwork(targetChainId) {
  if (!window.ethereum) return;
  const hex = "0x" + targetChainId.toString(16);
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hex }] });
  } catch (e) {
    if (e.code === 4902) {
      const isTest = targetChainId === CONFIG.chainIdTestnet;
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: hex,
          chainName: isTest ? "BNB Smart Chain Testnet" : "BNB Smart Chain",
          nativeCurrency: { name: isTest ? "tBNB" : "BNB", symbol: isTest ? "tBNB" : "BNB", decimals: 18 },
          rpcUrls: [isTest ? CONFIG.rpcTestnet : CONFIG.rpcMainnet],
          blockExplorerUrls: [isTest ? CONFIG.explorerTestnet : CONFIG.explorerMainnet],
        }],
      });
    } else {
      throw e;
    }
  }
}

async function connect() {
  if (typeof ethers === "undefined") {
    alert("Could not load the ethers.js library (CDN unreachable). Check your connection and reload.");
    return;
  }
  if (!window.ethereum) {
    alert("No wallet found. Install a wallet with an injected provider (e.g. Binance Wallet) and reload.");
    return;
  }
  try {
    provider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    account = accounts[0];
    signer = await provider.getSigner();
    chainId = Number((await provider.getNetwork()).chainId);
    readProvider = new ethers.JsonRpcProvider(rpcUrl());
    $("connectBtn").textContent = "Connected";
    $("connectBtn").disabled = true;
    const addrEl = $("walletAddr");
    addrEl.textContent = short(account);
    addrEl.classList.remove("hidden");
    $("networkBar").classList.remove("hidden");
    $("networkName").textContent = chainId === 56 ? "BSC Mainnet"
      : chainId === 97 ? "BSC Testnet" : `chain ${chainId} (unsupported — switch below)`;
    updateDeployUI();
    await refreshAll();
    await loadFeed();
  } catch (e) {
    alert("Wallet connection failed: " + ((e && e.message) || e));
  }
}

function updateDeployUI() {
  const warn = $("deployWarning");
  const link = $("contractLink");
  if (deployed()) {
    warn.classList.add("hidden");
    link.href = `${explorer()}/address/${streakAddress()}`;
    link.textContent = "View contract on BscScan";
  } else {
    warn.classList.remove("hidden");
    link.href = CONFIG.repoUrl;
    link.textContent = "View contract on BscScan (after deploy)";
  }
  $("repoLink").href = CONFIG.repoUrl;
}

function init() {
  $("repoLink").href = CONFIG.repoUrl;
  $("connectBtn").onclick = connect;
  $("checkInBtn").onclick = doCheckIn;
  $("switchMainnetBtn").onclick = () => switchNetwork(CONFIG.chainId).then(() => location.reload()).catch((e) => alert(e.message || e));
  $("switchTestnetBtn").onclick = () => switchNetwork(CONFIG.chainIdTestnet).then(() => location.reload()).catch((e) => alert(e.message || e));
  // Read-only mode: feed + deploy banner work without a wallet.
  chainId = CONFIG.chainId;
  readProvider = new ethers.JsonRpcProvider(rpcUrl());
  updateDeployUI();
  loadFeed();
  refreshBadges();
  if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
  }
}

if (typeof ethers === "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    $("feedNote").textContent = "Could not load the ethers.js library (CDN unreachable). Reload to retry.";
  });
} else {
  document.addEventListener("DOMContentLoaded", init);
}
