# Spoxy-Gang

## SpoxyFun V2 mint rules

- Total collection supply: 2,222 NFTs.
- Free mint: up to 800 total; Binance Agent ID required; maximum 3 free mints per wallet.
- Paid mint: 0.001 BNB each, available immediately to any wallet, including wallets that hold an Agent ID. Paid mint does not consume the free-mint quota.
- Both mint methods share the collection supply and require the owner to open minting.

The V2 Solidity source is [`contracts/SpoxyFun.sol`](contracts/SpoxyFun.sol), its compiled artifact is [`contracts/SpoxyFunV2.json`](contracts/SpoxyFunV2.json), and tests are in [`contracts/SpoxyFun.t.sol`](contracts/SpoxyFun.t.sol). Use [`spoxyfun-deploy.html`](spoxyfun-deploy.html) to deploy the new contract from a BNB Chain wallet.

**Important:** an already-deployed contract cannot be deleted from the blockchain. V2 is a separate deployment. Do not enable the mint UI or replace the deployed website until the V2 contract has been deployed, verified, and its address has been placed into the frontend configuration. The frontend mint address is intentionally blank until then, to avoid sending transactions to the old contract.
