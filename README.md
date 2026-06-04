# ConsssLab Contracts

Smart contracts for **ConSSS Wars: Echoes of Chainoa 鏈州英雄傳** — a
turn-based tactical RPG that mints "Chronicle" NFTs after each battle. Game
spec lives in `../docs/`.

## Layout

| Folder    | Chain    | Status                                          |
|-----------|----------|-------------------------------------------------|
| `sui/`    | Sui      | **Deployed to testnet (latest 2026-06-03, version-gated)** |
| `evm/`    | EVM      | Skeleton — flesh out post-hackathon              |
| `solana/` | Solana   | Skeleton — flesh out post-hackathon              |

Hackathon focus: the **Tatum × Build on Sui with Walrus** track (deadline
2026-06-06). Sui is the primary chain; EVM and Solana skeletons are kept
in-tree for the BSC chapter DLC and Solana chapter DLC respectively.

## Sui deployment (testnet)

The canonical record lives in [`sui/Published.toml`](./sui/Published.toml)
(committed; `Move.lock` is gitignored).

| Object | ID |
|--------|----|
| `chronicle` package | `0x5efb10426a8929e88510dbc80711e2bf371aca08b179167b3037e20d097f6980` |
| `ChronicleRegistry` (shared) | `0x19b9f0fe18ea27a56f75b6d6302e00e80a9bf1656c81f87eecbb82a4bc3109ee` |
| `WitnessRegistry` (shared) | `0x7359529def5f8a225e6e7c460ff44ee4f276bdd5ce50c0c7b1e10faaa3e831d0` |
| `UpgradeCap` | `0xe13be9e1c8c6228014d3ccc1d385cb422e9e57ec34da7713a226ed76bec249a8` |

Chain ID: `4c78adac` (Sui testnet). RPC traffic goes through
**Tatum** (`https://sui-testnet.gateway.tatum.io`) per the hackathon track
requirement.

## NFT model

Two modules in `sui/sources/`, mirrored field-by-field across chains:

- **`chronicle::chronicle`** — transferable battle keepsake.
  `mint_chronicle(...)` records `battle_id`, `hero_id`, player-edited
  `title` / `inscription`, an on-chain-computed `tier` (Normal/Bronze/Silver/Gold,
  from per-battle clear-rank + HP), global `mint_order`,
  `is_first_chronicler`, `mint_timestamp_ms`, the player's address, and a
  **`metadata_blob_id`** anchor pointing at the long-form battle log stored
  on Walrus. A shared `ChronicleRegistry` keeps a per-`battle_id` counter
  so each NFT knows which numbered chronicler the player is.
- **`chronicle::witness_seal`** — soulbound Validators' Witness; once per
  player, Battle 3 only. Struct omits the `store` ability and exposes no
  transfer entry function.

### Walrus integration

`metadata_blob_id` is the Walrus blob ID returned by the dApp client after
PUT-ing the player's edited Chronicle JSON to the Walrus publisher. The
Sui Move Display fields embed the aggregator URL template
`https://aggregator.walrus-testnet.walrus.space/v1/blobs/{metadata_blob_id}`
so any indexer / wallet that resolves the Display can fetch the off-chain
payload without an extra contract call.

Canonical mint flow (covered end-to-end by `app/`):

1. Player completes battle → `app/` builds Chronicle JSON.
2. dApp client uploads JSON to Walrus publisher → receives `blob_id`.
3. dApp client signs `mint_chronicle(...)` Tx with `metadata_blob_id = blob_id`.
4. Sui chain emits `ChronicleMinted` event; NFT lands in the player's wallet.

## Build / test

Sui is the active chain; EVM and Solana are skeletons.

- **Sui** — `cd sui && sui move build && sui move test`
  (14 tests currently passing across `chronicle_tests.move` + `witness_seal_tests.move`).
- **EVM** — `cd evm && forge build && forge test` (skeleton).
- **Solana** — `cd solana && anchor build && anchor test` (skeleton).

## Publish a new version (Sui)

Only required for non-backwards-compatible logic changes. Backwards-compatible
changes go through `sui client upgrade` with the `UpgradeCap` above; the
package ID is preserved and consumers don't need to rebuild.

```bash
cd sui
sui client publish --gas-budget 200000000
```

After publish, copy the resulting package + shared-registry IDs back into
`Published.toml` and into `app/godot/web/config.local.js` so the bundle
points at the new deployment.

## Repository conventions

- **No tokens, no presale, no airdrop.** Chronicle mint is gas-only; the
  team takes no cut. Soulbound `WitnessSeal` is non-transferable by design.
- `Published.toml` is the single source of truth for deployed addresses.
  `Move.lock` stays gitignored (toolchain-local; can diverge between machines).
- Public-bound repo: **no real-person names**, no team-internal docs.
  Real-person design originals live in `../docs/` (private). See `.gitignore`
  for the keystore / `.env` / wallet / coverage patterns it blocks.
- Deployer wallet (`SuiAudit-Publisher`,
  `0x285b0021863629b449109da710cee9969354a181a426781da74b510ea1d018d9`)
  holds the `UpgradeCap`. The private key is **not** in this repo.
