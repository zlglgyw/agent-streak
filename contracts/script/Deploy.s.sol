// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AgentStreak} from "../src/AgentStreak.sol";
import {MockAgentId} from "../src/MockAgentId.sol";

/// @notice Deploy AgentStreak.
///         Env vars:
///           PRIVATE_KEY (required) — deployer key.
///           AGENT_ID (optional)    — Agent ID contract address.
///             Mainnet: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
///             Unset: deploys MockAgentId first (testnet/local) and mints
///             one mock Agent ID to the deployer for e2e tests.
///           OWNER (optional)       — owner address; defaults to the deployer.
///         Run with: forge script script/Deploy.s.sol --rpc-url <url>
///                   --broadcast   (key via PRIVATE_KEY env var)
///         NEVER run against mainnet without explicit approval.
contract Deploy is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address agentId = vm.envOr("AGENT_ID", address(0));
        address owner = vm.envOr("OWNER", deployer);

        vm.startBroadcast(deployerKey);

        if (agentId == address(0)) {
            MockAgentId mock = new MockAgentId();
            agentId = address(mock);
            console.log("MockAgentId deployed:", agentId);
            mock.mint(deployer);
            console.log("Mock Agent ID minted to deployer:", deployer);
        } else {
            console.log("Using Agent ID:", agentId);
        }

        AgentStreak streak = new AgentStreak(agentId, owner);
        console.log("AgentStreak deployed:", address(streak));
        console.log("Owner:", owner);

        vm.stopBroadcast();
    }
}
