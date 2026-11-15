// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SpoxyStaking — stake SpoxyFun ghosts, earn WISP
/// @notice Rewards accrue per second at REWARD_PER_DAY per staked ghost.
/// Staking starts CLOSED; the owner opens it (planned: after mint ends).
/// Unstaking is NEVER gated: a staker can always exit. Claiming costs
/// CLAIM_FEE in BNB, which settles in this contract; the owner withdraws
/// accumulated fees via withdraw(). Accrued rewards are settled into a
/// per-user pending balance on every stake/unstake/claim, so unstaking
/// never forfeits earned rewards — they stay claimable afterwards.
/// @dev The SpoxyFun NFT is NOT ERC721Enumerable, so this contract cannot
/// enumerate a wallet's ghosts on-chain. Agents discover token IDs from
/// the wallet's holdings/transfer history and stake them in one batch
/// via stakeMany(). No function here lists owned token IDs.
contract SpoxyStaking is Ownable, ReentrancyGuard, IERC721Receiver {
    IERC721 public immutable nft;
    IERC20 public immutable rewardToken;

    /// @notice WISP earned per staked ghost per day (10 WISP, 18 decimals).
    uint256 public constant REWARD_PER_DAY = 10 ether;
    /// @notice BNB fee per claim, kept in this contract.
    uint256 public constant CLAIM_FEE = 0.0001 ether;

    bool public stakingOpen;

    /// @notice tokenId -> staker address (address(0) = not staked).
    mapping(uint256 => address) public stakedBy;
    mapping(address => uint256) public stakedCount;
    /// @notice Settled (already accrued) rewards awaiting claim.
    mapping(address => uint256) public pendingRewards;
    /// @notice Last timestamp at which `pendingRewards` was settled.
    mapping(address => uint256) public lastSettled;

    error StakingClosed();
    error EmptyArray();
    error NotTokenOwner(uint256 tokenId);
    error AlreadyStaked(uint256 tokenId);
    error NotStaker(uint256 tokenId);
    error NoRewards();
    error InsufficientPayment();
    error InsufficientRewards();
    error TransferFailed();
    error NothingToWithdraw();
    error NotHeldByContract(uint256 tokenId);
    error ZeroAddress();

    event Staked(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event Claimed(address indexed user, uint256 amount);
    event StakingOpenChanged(bool open);
    event Withdrawn(address indexed to, uint256 amount);
    event Rescued(uint256 indexed tokenId, address indexed to);

    constructor(address _nft, address _rewardToken) Ownable(msg.sender) {
        if (_nft == address(0) || _rewardToken == address(0)) revert ZeroAddress();
        nft = IERC721(_nft);
        rewardToken = IERC20(_rewardToken);
    }

    // ── Owner ────────────────────────────────────────────────────────────

    function setStakingOpen(bool open) external onlyOwner {
        stakingOpen = open;
        emit StakingOpenChanged(open);
    }

    /// @notice Withdraw accumulated BNB claim fees to the owner.
    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        (bool ok,) = owner().call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(owner(), bal);
    }

    /// @notice Rescue an NFT that was sent to this contract by mistake
    /// (direct transfer without staking). Can NEVER take a staked ghost:
    /// staked tokenIds revert.
    function rescueStuckNFT(uint256 tokenId, address to) external onlyOwner {
        if (stakedBy[tokenId] != address(0)) revert AlreadyStaked(tokenId);
        if (nft.ownerOf(tokenId) != address(this)) revert NotHeldByContract(tokenId);
        nft.transferFrom(address(this), to, tokenId);
        emit Rescued(tokenId, to);
    }

    // ── Views ────────────────────────────────────────────────────────────

    /// @notice Total claimable WISP for `user`, including un-settled accrual.
    function pending(address user) external view returns (uint256) {
        uint256 p = pendingRewards[user];
        if (stakedCount[user] > 0) {
            p += (block.timestamp - lastSettled[user]) * stakedCount[user] * REWARD_PER_DAY / 1 days;
        }
        return p;
    }

    // ── Staking ──────────────────────────────────────────────────────────

    function stake(uint256 tokenId) external nonReentrant {
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        _stakeMany(ids);
    }

    /// @notice Stake several ghosts in one transaction. The caller must own
    /// every tokenId and must have approved this contract (approve per
    /// token, or setApprovalForAll once). Agents: discover the wallet's
    /// ghost IDs from holdings/transfer history, then call this once.
    function stakeMany(uint256[] calldata tokenIds) external nonReentrant {
        _stakeMany(tokenIds);
    }

    function _stakeMany(uint256[] memory tokenIds) internal {
        if (!stakingOpen) revert StakingClosed();
        if (tokenIds.length == 0) revert EmptyArray();
        _settle(msg.sender);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (stakedBy[tokenId] != address(0)) revert AlreadyStaked(tokenId);
            if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner(tokenId);
            stakedBy[tokenId] = msg.sender;
            nft.transferFrom(msg.sender, address(this), tokenId);
            emit Staked(msg.sender, tokenId);
        }
        stakedCount[msg.sender] += tokenIds.length;
    }

    function unstake(uint256 tokenId) external nonReentrant {
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        _unstakeMany(ids);
    }

    /// @notice Unstake several ghosts in one transaction. Always allowed,
    /// even while staking is closed. Accrued rewards are settled into the
    /// pending balance and stay claimable afterwards.
    function unstakeMany(uint256[] calldata tokenIds) external nonReentrant {
        _unstakeMany(tokenIds);
    }

    function _unstakeMany(uint256[] memory tokenIds) internal {
        if (tokenIds.length == 0) revert EmptyArray();
        _settle(msg.sender);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (stakedBy[tokenId] != msg.sender) revert NotStaker(tokenId);
            delete stakedBy[tokenId];
            nft.transferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, tokenId);
        }
        stakedCount[msg.sender] -= tokenIds.length;
    }

    // ── Claiming ─────────────────────────────────────────────────────────

    /// @notice Claim all pending WISP. Costs exactly CLAIM_FEE in BNB
    /// (excess is refunded); the fee stays in this contract.
    function claim() external payable nonReentrant {
        if (msg.value < CLAIM_FEE) revert InsufficientPayment();
        _settle(msg.sender);
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) revert NoRewards();
        if (rewardToken.balanceOf(address(this)) < amount) revert InsufficientRewards();
        pendingRewards[msg.sender] = 0;
        uint256 excess = msg.value - CLAIM_FEE;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert TransferFailed();
        }
        if (!rewardToken.transfer(msg.sender, amount)) revert TransferFailed();
        emit Claimed(msg.sender, amount);
    }

    // ── Internal ─────────────────────────────────────────────────────────

    /// @notice Roll time-based accrual into `pendingRewards[user]` up to now.
    function _settle(address user) internal {
        if (stakedCount[user] == 0) {
            lastSettled[user] = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastSettled[user];
        if (elapsed > 0) {
            pendingRewards[user] += elapsed * stakedCount[user] * REWARD_PER_DAY / 1 days;
        }
        lastSettled[user] = block.timestamp;
    }

    /// @notice Accept safe transfers (required for safeTransferFrom flows).
    /// Ghosts sent here directly are NOT staked; the owner can rescue them
    /// via rescueStuckNFT(). Always stake through stake()/stakeMany().
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
