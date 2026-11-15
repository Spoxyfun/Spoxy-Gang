// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Wisp — SpoxyFun staking reward token
/// @notice Fixed supply, minted once to the deployer. No mint, burn, pause,
/// or owner functions: the supply can never change after deployment.
/// @dev Planned split (done by the deployer after deployment, not enforced
/// here): 50M reward pool -> SpoxyStaking contract, 45M LP, 5M owner.
contract Wisp is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 100_000_000 ether;

    constructor() ERC20("Wisp", "WISP") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
