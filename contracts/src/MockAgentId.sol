// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title MockAgentId
/// @notice TESTNET-ONLY mock of the SPACE ID Agent ID contract.
///         The real Agent ID contract does not exist on BSC Testnet, so
///         testnet deployments of AgentStreak point at this mock instead.
///         Anyone can mint — it exists purely to exercise the holder gate.
///         NEVER use on mainnet: mainnet uses the real Agent ID contract
///         0x60b9262456de011f7d15a54cdd8c48baaa8b022f.
contract MockAgentId is ERC721 {
    uint256 private _nextId;

    constructor() ERC721("Mock Agent ID", "MOCKID") {}

    function mint(address to) external returns (uint256) {
        uint256 id = ++_nextId;
        _mint(to, id);
        return id;
    }
}
