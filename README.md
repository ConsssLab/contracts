# ConsssLabs Contracts

Smart contracts for **ConSSS Wars: Echoes of Chainoa** — a 2.5D action RPG that mints
"Chronicle" NFTs after each battle. Authoritative game spec lives in
`../ConsssLabs-docs/`.

## Layout

| Folder    | Chain    | Status                              |
|-----------|----------|-------------------------------------|
| `sui/`    | Sui      | **Primary** — W6 testnet target     |
| `evm/`    | EVM      | Skeleton only — flesh out in W8     |
| `solana/` | Solana   | Skeleton only — flesh out in W8     |

## NFT model (cross-chain)

Both `Chronicle` (transferable) and `WitnessSeal` (soulbound, Battle 3 only)
encode the same fields: `battle_id`, `hero_id`, player-edited `title` /
`inscription`, system-graded `rating`, global `mint_order`, `is_first_chronicler`,
`block_height_at_mint`, and the player's address. See
`../ConsssLabs-docs/business/model.md` for the canonical rules.

## Build / test

Each chain folder has its own `README.md` with the exact toolchain commands.
Quick references:

- **Sui** — `cd sui && sui move build && sui move test`
- **EVM** — `cd evm && forge build && forge test`
- **Solana** — `cd solana && anchor build && anchor test`

## Repository conventions

- No tokens, no presale, no airdrop. Chronicle mint is **gas-only**; the team
  takes no cut. Soulbound `WitnessSeal` is non-transferable by design.
- All on-chain art URLs use the placeholder
  `https://chainoa.consss.io/chronicle/{id}.png` until W7 art lands.
