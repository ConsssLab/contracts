# ConsssLab Contracts

On-chain contracts for **ConSSS Wars: Echoes of Chainoa（鏈州英雄傳：鏈之迴響）**,
a turn-based tactical RPG. Players mint a **Chronicle** NFT after each battle, a
soulbound **Finale Badge** for clearing the climax, and a limited-time event
rewards players who clear the full campaign. Game design lives in `../docs/`
(private).

> No token. No presale. No airdrop. Minting is gas-only — the team takes no cut.

## Chains

| Folder    | Chain  | Status                                                  |
|-----------|--------|--------------------------------------------------------|
| `sui/`    | Sui    | **Primary — production.** All gameplay NFTs live here.  |
| `evm/`    | EVM    | Reserved placeholder for a future cross-chain chapter.  |
| `solana/` | Solana | Reserved placeholder for a future cross-chain chapter.  |

Built for the **Tatum × Build on Sui with Walrus** track. Sui is the canonical
chain; `evm/` and `solana/` are intentionally empty, held in-tree for later
chapters.

## Packages (`sui/`)

| Package         | Module(s)                        | Mints                                                       |
|-----------------|----------------------------------|------------------------------------------------------------|
| `chronicle`     | `chronicle`, `echoes_of_chainoa` | Per-battle **Chronicle** (transferable, tiered) + soulbound **Finale Badge** |
| `event_01_gift` | `event_01_gift`                  | Limited-time **"1st Gift"** for clearing battles 1–3        |

`event_01_gift` verifies Chronicle ownership, so it depends on `chronicle` —
publish `chronicle` first.

### `chronicle::chronicle` — battle Chronicle
Transferable keepsake, one per battle clear. Records `battle_id`, `hero_id`,
player-edited `title`/`inscription`, an on-chain-computed `tier`
(Normal/Bronze/Silver/Gold, from per-battle clear-rank + HP), `mint_order`,
`is_first_chronicler`, timestamp, the player address, and a Walrus
`metadata_blob_id` anchoring the long-form battle log. A shared
`ChronicleRegistry` holds the per-battle counter, the voucher authority key, and
admin-configurable `max_battle_id`/`max_hero_id` (so new chapters need no code
change).

### `chronicle::echoes_of_chainoa` — Finale Badge
Soulbound (`key`-only, no `store`, no transfer entry) badge for clearing the
climax battle; one per player, enforced by the shared `FinaleRegistry`.

### `event_01_gift` — limited-time event
A wallet may mint exactly one Gift, only while the event is open (on-chain
`end_ms` deadline), and only if it holds Chronicles **earned by that wallet**
(the `player` field must equal the caller) covering three distinct battles
{1, 2, 3}. Numbered (`event_01_…`) so future events get their own module.

## Anti-cheat: authority vouchers
A client cannot mint by crafting a transaction directly — `mint_chronicle` and
`mint_finale` require an **ed25519 voucher** signed by an off-chain authority key
the game backend controls. The signed message is:

```
DOMAIN ++ registry_id(32) ++ player(32) ++ battle_id ++ hero_id
       ++ hp_pct|rating ++ nonce(u64 LE) ++ expiry_ms(u64 LE)
```

- **Domain separator** (`ConSSSWars/chronicle-voucher/v1`; a distinct one for
  finale) binds a signature to this contract and purpose.
- **`registry_id`** binds it to this exact deployment — no cross-deployment replay.
- **`nonce`** (kept in `used_nonces`) blocks replay; **`expiry_ms`** vs the
  on-chain `Clock` blocks stale reuse; the 64-byte signature length is checked.

The backend signer is `play/functions/[[path]].js` (`buildVoucherMessage`); the
on-chain message is locked to it byte-for-byte by the
`chronicle::voucher_message_byte_layout` test.

## Governance (capabilities)

| Capability                    | Holder                    | Purpose                                            |
|-------------------------------|---------------------------|----------------------------------------------------|
| `chronicle::AdminCap`         | 2/3 multisig (cold)       | rotate authority key, pause, set caps, migrate     |
| `event_01_gift::GiftAdminCap` | 2/3 multisig (cold)       | pause, set deadline, migrate, burn after the event |
| `UpgradeCap` ×2               | 2/3 multisig (cold)       | package upgrades                                   |
| `Publisher` ×N                | 2/3 multisig (cold)       | Display administration                             |
| `Display` ×N                  | operational wallet (hot)  | update NFT art metadata                            |

No capability or private key lives in this repo. Every entry point is backed by a
version gate (`VERSION` / `assert_active` / `migrate`) and a `paused` switch.

## Walrus
`metadata_blob_id` is the Walrus blob ID the dApp receives after uploading the
player's Chronicle JSON. The Move `Display` embeds the aggregator URL template, so
any wallet/indexer resolving the Display can fetch the off-chain payload without
an extra contract call.

## Build & test

```bash
cd sui/chronicle     && sui move build && sui move test   # 12 tests
cd sui/event_01_gift && sui move build && sui move test   #  6 tests
```

## Deploy
`Published.toml` (per package, committed) is the single source of truth for
deployed addresses; `Move.lock` is toolchain-local. Publish order: `chronicle`
first, then `event_01_gift`. After publishing, set the voucher authority key
(`set_authority_pubkey`) and transfer the capabilities to the multisig. The full
mainnet + multisig runbook lives in `../docs/deploy/` (private).

## Conventions
- Public repo: **no real-person names**, no team-internal docs (those live in
  `../docs/`, private). See `.gitignore` for blocked keystore / `.env` / wallet
  patterns.
- `Published.toml` is the source of truth for deployed addresses; consumers read
  IDs from config, never hand-edited into source.
