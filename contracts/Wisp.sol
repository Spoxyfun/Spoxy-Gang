// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Wisp (WISP)
/// @notice Fixed-supply SpoxyFun token for rewards, liquidity, and paid-NFT airdrop.
/// @dev The full supply is minted once to the deployer. There is no mint,
/// burn, pause, tax, blacklist, or owner-controlled supply function.
contract Wisp is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 2_500_000 ether;

    constructor() ERC20("Wisp", "WISP") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
