// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SpoxyStaking7Day
/// @notice One global seven-day WISP reward campaign for SpoxyFun NFTs.
/// @dev The already deployed SpoxyFun NFT does not expose a per-token
/// free/paid view. Before starting the campaign, the owner must classify paid
/// token IDs from the SpoxyMinted events using setPaidTokenIds(). Unclassified
/// NFTs earn the free rate. Classification becomes immutable at campaign start.
/// Fund this contract with at least MAX_CAMPAIGN_REWARDS before startCampaign().
contract SpoxyStaking7Day is Ownable, ReentrancyGuard, IERC721Receiver {
    IERC721 public immutable nft;
    IERC20 public immutable rewardToken;

    uint256 public constant CAMPAIGN_DURATION = 7 days;
    uint256 public constant FREE_REWARD_PER_DAY = 10 ether;
    uint256 public constant PAID_REWARD_PER_DAY = 50 ether;
    uint256 public constant STAKE_FEE = 0.0001 ether;
    uint256 public constant UNSTAKE_FEE = 0.0001 ether;
    uint256 public constant CLAIM_FEE = 0.0001 ether;
    uint256 public constant MAX_NFT_SUPPLY = 2222;
    /// @notice Worst case: all collection NFTs earn the paid rate for 7 days.
    uint256 public constant MAX_CAMPAIGN_REWARDS =
        MAX_NFT_SUPPLY * PAID_REWARD_PER_DAY * CAMPAIGN_DURATION / 1 days;

    uint256 public campaignStart;
    uint256 public campaignEnd;

    mapping(uint256 => bool) public isPaidToken;
    mapping(uint256 => address) public stakedBy;
    mapping(address => uint256) public freeStakedCount;
    mapping(address => uint256) public paidStakedCount;
    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public lastSettled;

    error ZeroAddress();
    error CampaignAlreadyStarted();
    error CampaignNotStarted();
    error CampaignEnded();
    error InsufficientRewardFunding(uint256 required, uint256 available);
    error EmptyArray();
    error NotTokenOwner(uint256 tokenId);
    error AlreadyStaked(uint256 tokenId);
    error NotStaker(uint256 tokenId);
    error NoRewards();
    error InsufficientPayment(uint256 required, uint256 sent);
    error InsufficientRewards(uint256 required, uint256 available);
    error TransferFailed();
    error NothingToWithdraw();
    error NotHeldByContract(uint256 tokenId);
    error UnexpectedNFT();

    event PaidTokenClassified(uint256 indexed tokenId, bool paid);
    event CampaignStarted(uint256 startTime, uint256 endTime, uint256 fundedRewards);
    event Staked(address indexed user, uint256 indexed tokenId, bool paid);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event Claimed(address indexed user, uint256 amount);
    event FeeCollected(address indexed user, bytes4 indexed action, uint256 amount);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event Rescued(uint256 indexed tokenId, address indexed to);

    constructor(address nftAddress, address rewardTokenAddress) Ownable(msg.sender) {
        if (nftAddress == address(0) || rewardTokenAddress == address(0)) revert ZeroAddress();
        nft = IERC721(nftAddress);
        rewardToken = IERC20(rewardTokenAddress);
    }

    /// @notice Record paid NFT IDs from the SpoxyFun SpoxyMinted events.
    /// @dev May only be called before the one-time campaign starts.
    function setPaidTokenIds(uint256[] calldata tokenIds, bool paid) external onlyOwner {
        if (campaignStart != 0) revert CampaignAlreadyStarted();
        if (tokenIds.length == 0) revert EmptyArray();
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            // ownerOf reverts for an NFT that has not been minted.
            nft.ownerOf(tokenId);
            if (stakedBy[tokenId] != address(0)) revert AlreadyStaked(tokenId);
            isPaidToken[tokenId] = paid;
            emit PaidTokenClassified(tokenId, paid);
        }
    }

    /// @notice Start the single seven-day campaign after funding the reward pool.
    /// @dev Campaign cannot be paused or restarted. Any rewards accrued in the
    /// seven-day window remain claimable after campaignEnd.
    function startCampaign() external onlyOwner {
        if (campaignStart != 0) revert CampaignAlreadyStarted();
        uint256 funded = rewardToken.balanceOf(address(this));
        if (funded < MAX_CAMPAIGN_REWARDS) {
            revert InsufficientRewardFunding(MAX_CAMPAIGN_REWARDS, funded);
        }
        campaignStart = block.timestamp;
        campaignEnd = block.timestamp + CAMPAIGN_DURATION;
        emit CampaignStarted(campaignStart, campaignEnd, funded);
    }

    /// @notice Stake one SpoxyFun NFT during the campaign window.
    function stake(uint256 tokenId) external payable nonReentrant {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        _stakeMany(tokenIds);
    }

    /// @notice Stake multiple SpoxyFun NFTs in one transaction.
    /// @dev Caller must first approve this contract for each token or use
    /// setApprovalForAll on the NFT contract.
    function stakeMany(uint256[] calldata tokenIds) external payable nonReentrant {
        _stakeMany(tokenIds);
    }

    function _stakeMany(uint256[] memory tokenIds) internal {
        if (campaignStart == 0) revert CampaignNotStarted();
        if (block.timestamp >= campaignEnd) revert CampaignEnded();
        if (tokenIds.length == 0) revert EmptyArray();
        _chargeFee(STAKE_FEE);

        _settle(msg.sender);
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (stakedBy[tokenId] != address(0)) revert AlreadyStaked(tokenId);
            if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner(tokenId);

            bool paid = isPaidToken[tokenId];
            stakedBy[tokenId] = msg.sender;
            if (paid) paidStakedCount[msg.sender] += 1;
            else freeStakedCount[msg.sender] += 1;

            nft.transferFrom(msg.sender, address(this), tokenId);
            emit Staked(msg.sender, tokenId, paid);
        }
    }

    /// @notice Unstake at any time, including after the seven-day campaign.
    /// Accrued rewards are retained and may still be claimed later.
    function unstake(uint256 tokenId) external payable nonReentrant {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        _unstakeMany(tokenIds);
    }

    function unstakeMany(uint256[] calldata tokenIds) external payable nonReentrant {
        _unstakeMany(tokenIds);
    }

    function _unstakeMany(uint256[] memory tokenIds) internal {
        if (tokenIds.length == 0) revert EmptyArray();
        _chargeFee(UNSTAKE_FEE);
        _settle(msg.sender);
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (stakedBy[tokenId] != msg.sender) revert NotStaker(tokenId);
            delete stakedBy[tokenId];
            if (isPaidToken[tokenId]) paidStakedCount[msg.sender] -= 1;
            else freeStakedCount[msg.sender] -= 1;
            nft.transferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, tokenId);
        }
    }

    /// @notice Pending WISP includes reward accrual up to min(now, campaignEnd).
    function pending(address user) external view returns (uint256) {
        return pendingRewards[user] + _unsettledReward(user);
    }

    /// @notice Claim all rewards. Requires 0.0001 BNB; excess is refunded.
    /// Claims remain available after the seven-day earning window ends.
    function claim() external payable nonReentrant {
        _chargeFee(CLAIM_FEE);
        _settle(msg.sender);
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) revert NoRewards();
        uint256 available = rewardToken.balanceOf(address(this));
        if (available < amount) revert InsufficientRewards(amount, available);

        pendingRewards[msg.sender] = 0;
        if (!rewardToken.transfer(msg.sender, amount)) revert TransferFailed();
        emit Claimed(msg.sender, amount);
    }

    /// @notice Withdraw accumulated stake, unstake, and claim fees to the owner.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool ok,) = payable(owner()).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesWithdrawn(owner(), amount);
    }

    /// @notice Rescue an NFT sent directly to this contract by mistake.
    /// Staked NFTs cannot be rescued by the owner.
    function rescueStuckNFT(uint256 tokenId, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (stakedBy[tokenId] != address(0)) revert AlreadyStaked(tokenId);
        if (nft.ownerOf(tokenId) != address(this)) revert NotHeldByContract(tokenId);
        nft.transferFrom(address(this), to, tokenId);
        emit Rescued(tokenId, to);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != address(nft)) revert UnexpectedNFT();
        return IERC721Receiver.onERC721Received.selector;
    }

    function _chargeFee(uint256 fee) internal {
        if (msg.value < fee) revert InsufficientPayment(fee, msg.value);
        uint256 excess = msg.value - fee;
        if (excess != 0) {
            (bool refunded,) = payable(msg.sender).call{value: excess}("");
            if (!refunded) revert TransferFailed();
        }
        emit FeeCollected(msg.sender, msg.sig, fee);
    }

    function _settle(address user) internal {
        if (campaignStart == 0) return;
        uint256 settleAt = block.timestamp < campaignEnd ? block.timestamp : campaignEnd;
        if (lastSettled[user] == 0) {
            lastSettled[user] = settleAt;
            return;
        }
        uint256 accrued = _unsettledReward(user);
        if (accrued != 0) pendingRewards[user] += accrued;
        if (lastSettled[user] < settleAt) lastSettled[user] = settleAt;
    }

    function _unsettledReward(address user) internal view returns (uint256) {
        if (campaignStart == 0 || lastSettled[user] == 0) return 0;
        uint256 settleAt = block.timestamp < campaignEnd ? block.timestamp : campaignEnd;
        if (settleAt <= lastSettled[user]) return 0;
        uint256 dailyRate = freeStakedCount[user] * FREE_REWARD_PER_DAY
            + paidStakedCount[user] * PAID_REWARD_PER_DAY;
        return (settleAt - lastSettled[user]) * dailyRate / 1 days;
    }
}
