# WISP 7-Day Staking Contracts

## Token allocation

- **Total fixed supply:** 2,500,000 WISP (18 decimals).
- **Staking rewards:** 1,000,000 WISP.
- **PancakeSwap liquidity allocation:** 1,000,000 WISP.
- **Paid-NFT holder airdrop allocation:** 500,000 WISP.

The token contract mints the entire fixed supply to its deployer once. It has no further mint, burn, pause, tax, blacklist, or owner-controlled supply function. The allocations above are operational allocations and must be made by transfers after the relevant contracts/wallets are ready; the token contract does not itself enforce the split. Airdrop eligibility and per-holder distribution are not encoded yet: the project still needs to select a snapshot block/time and decide whether the 500,000 WISP is divided per eligible NFT or per wallet.

## Included sources

- `Wisp.sol`: fixed WISP token supply.
- `SpoxyStaking7Day.sol`: one owner-started campaign lasting exactly seven days. Free NFTs accrue 10 WISP/day; paid NFTs accrue 50 WISP/day. New stakes are accepted only during the seven-day window. Accrued rewards remain claimable after it ends, and NFTs can always be unstaked.

Each `stake`/`stakeMany`, `unstake`/`unstakeMany`, and `claim` transaction costs **0.0001 BNB per transaction**. A batch transaction is charged once regardless of how many NFTs it contains. Any excess BNB is refunded. Fees are held by the staking contract and can be withdrawn by its owner.

The maximum reward requirement is **777,700 WISP**, calculated conservatively as 2,222 NFTs × 50 WISP/day × 7 days. The staking contract will refuse to start without at least this much WISP funded to it. The planned 1,000,000 WISP reward allocation leaves a 222,300 WISP buffer. The campaign cannot be paused or restarted. PancakeSwap listing is a separate operation and is not performed or guaranteed by these contracts.

## Important classification requirement

The already-deployed SpoxyFun NFT does not expose a per-token view that says whether a specific token was minted free or paid. The staking contract therefore defaults each token to the free reward rate. Before the campaign starts, the owner must collect paid token IDs from the NFT's `SpoxyMinted` event logs and register them using `setPaidTokenIds(ids, true)`. Classification becomes immutable once the campaign starts. If this step is skipped or IDs are wrong, affected NFTs will earn the free rate; the contract cannot independently verify mint provenance.

## Deployment and setup order

1. Deploy `Wisp.sol`; the deployer receives all 2,500,000 WISP.
2. Deploy `SpoxyStaking7Day.sol` with constructor arguments: the SpoxyFun NFT address and the WISP token address.
3. Transfer 1,000,000 WISP to the staking contract (at least 777,700 is required to start).
4. Before the campaign starts, register paid NFT IDs in manageable batches with `setPaidTokenIds(ids, true)`.
5. Call `startCampaign()` once. This starts the global seven-day clock.
6. NFT holders approve the staking contract on the SpoxyFun NFT, then call `stake(tokenId)` or `stakeMany(tokenIds)` with 0.0001 BNB once for the transaction.
7. Claim rewards with `claim()` and 0.0001 BNB. Users may unstake at any time, including after the campaign ends, by calling `unstake(tokenId)` or `unstakeMany(tokenIds)` with 0.0001 BNB once per transaction.
8. Keep 1,000,000 WISP allocated for PancakeSwap liquidity and 500,000 WISP for the paid-NFT holder airdrop. The liquidity's BNB side and the airdrop distribution rules must be decided separately.

## Scope and safety

These source files are **not deployed**. Review them, test them, and verify constructor addresses and the paid-token ID list before any production deployment. Do not treat deployment as the same action as listing WISP on PancakeSwap. A DEX listing additionally requires a chosen WISP/BNB liquidity amount, a wallet to seed it, and an explicit wallet transaction.
