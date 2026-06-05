# ConSSS Wars Contracts

On-chain contracts for **ConSSS Wars: Echoes of Chainoa（鏈州英雄傳：鏈之迴響）**, a
turn-based tactical RPG. Players mint a **Chronicle** NFT after each battle, a
soulbound **Finale Badge** for clearing the climax, and a one-per-wallet
limited-time **Gift** for completing the campaign. Sui is the primary chain.

> **No token. No presale. No airdrop.** Minting is gas-only — the team takes no
> cut. Game design and operational runbooks live in a separate private repo
> (`../docs/`).

## Status

**Live on Sui mainnet.** All gameplay NFTs are in production.

## Repository layout

| Folder    | Chain  | Status                                                  |
|-----------|--------|--------------------------------------------------------|
| `sui/`    | Sui    | **Primary — production.** All gameplay NFTs live here.  |
| `evm/`    | EVM    | Empty placeholder, reserved for a future chapter.      |
| `solana/` | Solana | Empty placeholder, reserved for a future chapter.      |

Sui is the canonical chain. `evm/` and `solana/` are intentionally empty
(`.gitkeep` only), held in-tree for later cross-chain chapters.

## Packages (`sui/`)

| Package         | Module(s)                        | Mints                                                                          |
|-----------------|----------------------------------|-------------------------------------------------------------------------------|
| `chronicle`     | `chronicle`, `echoes_of_chainoa` | Per-battle **Chronicle** (transferable, tiered) + soulbound **Finale Badge**  |
| `event_01_gift` | `event_01_gift`                  | One-per-wallet **"1st Gift"** for clearing battles 1–3                         |

`event_01_gift` checks `Chronicle` ownership at mint, so it depends on the
`chronicle` package — **publish `chronicle` first.**

### `chronicle::chronicle` — battle Chronicle

A transferable (`key + store`) keepsake, one mint per battle clear. It records
`battle_id`, `hero_id`, player-supplied `title`/`inscription`, the
voucher-attested `hp_pct`, an on-chain-computed `tier`, the per-battle
`mint_order`, `is_first_chronicler`, the mint timestamp, the `player` address,
and a Walrus `metadata_blob_id` anchoring the long-form battle log.

Tier is computed on-chain as **floor-by-rank, upgrade-by-HP** from the per-battle
mint rank held in the shared `ChronicleRegistry`:

| Per-battle rank | Floor  | `hp_pct >= 80` upgrades to | `tier` |
|-----------------|--------|----------------------------|--------|
| 1 – 100         | Silver | Gold                       | 2 → 3  |
| 101 – 300       | Bronze | Silver                     | 1 → 2  |
| 301 – 1000      | Normal | Bronze                     | 0 → 1  |
| 1001+           | —      | mint aborts (`ENoNFT`)     | —      |

One NFT type renders four visuals: the `Display` `image_url` is templated by
`{battle_id}` and `{tier}`. The `ChronicleRegistry` also holds the voucher
authority key, the spent-nonce set, and admin-configurable `max_battle_id` /
`max_hero_id` (defaults 3 / 20) so new chapters and heroes ship without a code
change.

### `chronicle::echoes_of_chainoa` — Finale Badge

A **soulbound** badge for clearing the installment's climax (Battle 3). The
`FinaleBadge` struct has `key` only (no `store`), exposes no transfer entry
function, and is delivered with `transfer::transfer`, so it can never move once
minted. One per player, enforced by the shared `FinaleRegistry`. The badge fixes
its battle forever; future installments ship their own finale module rather than
mutating this one.

### `event_01_gift::event_01_gift` — limited-time event

A wallet may mint exactly one Gift, only while the event is open (on-chain
`end_ms` deadline), and only by passing three `&Chronicle` it **earned itself**
(each Chronicle's `player` field must equal the caller) covering three distinct
battles within `{1, 2, 3}`. Binding to `player` blocks claiming with frozen or
transferred-in Chronicles. The numbered name (`event_01_…`) reserves the
namespace for future events.

## On-chain anti-cheat: authority vouchers

A client cannot mint by crafting a transaction directly. `mint_chronicle` and
`mint_finale` each require an **ed25519 voucher** signed by an off-chain
authority key the game backend controls; the voucher attests facts the client
cannot forge (remaining-HP%, finale clearance). The signed message is a
domain-prefixed BCS byte string:

```
DOMAIN ++ registry_id:address(32) ++ player:address(32)
       ++ battle_id:u8 ++ hero_id:u8 ++ (hp_pct|rating):u8
       ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
```

- **Domain separator** — `ConSSSWars/chronicle-voucher/v1` (a distinct
  `…/finale-voucher/v1` for the badge) binds a signature to this contract and
  purpose; the two vouchers cannot be cross-used.
- **`registry_id`** binds the voucher to this exact deployment — no
  cross-deployment replay.
- **`nonce`** (kept in `used_nonces`) blocks replay; **`expiry_ms`** vs the
  on-chain `Clock` blocks stale reuse; the signature must be exactly 64 bytes and
  the authority public key 32 bytes.

The on-chain message layout is pinned to the backend signer byte-for-byte by the
`chronicle::chronicle_tests::voucher_message_byte_layout` test.

## Walrus

`metadata_blob_id` is the Walrus blob ID the dApp receives after uploading the
player's Chronicle JSON (battle log, hero pose, screenshot, long text). The Move
`Display` embeds a Walrus aggregator URL template, so any wallet or indexer
resolving the Display can fetch the off-chain payload without an extra contract
call.

## Governance

Every player-facing entry point passes a version gate (`VERSION` /
`assert_active` / `migrate`) and a `paused` kill-switch. Capabilities are split
between a cold 2/3 multisig and a hot operational wallet:

| Capability                    | Holder                   | Purpose                                              |
|-------------------------------|--------------------------|------------------------------------------------------|
| `UpgradeCap` ×2               | 2/3 multisig (cold)      | Package upgrades                                     |
| `chronicle::AdminCap`         | 2/3 multisig (cold)      | Rotate authority key, pause, set caps, migrate       |
| `event_01_gift::GiftAdminCap` | 2/3 multisig (cold)      | Pause, set deadline, migrate, burn after the event   |
| `Publisher` ×3                | 2/3 multisig (cold)      | Display administration                               |
| `Display` ×3                  | operational wallet (hot) | Update NFT art metadata (no package upgrade needed)  |

No capability, key, or secret lives in this repo (see `.gitignore`).

## Deployments

Addresses below are mainnet. `Published.toml` (committed per package) is the
single source of truth for package IDs; consumers read object IDs from config
rather than hard-coding them into source.

**`chronicle` package** — `0x5760b2685d41bd45e2991dedc242e866b1aca9ff3c3a5e193445751c2b8dfe4b`

| Shared object       | ID                                                                   |
|---------------------|----------------------------------------------------------------------|
| `ChronicleRegistry` | `0x9ff1d9e50e8feca77ccddf5901bd774d3baa4732dac37ae261ca36b2352ced8b` |
| `FinaleRegistry`    | `0x2c752d82144701e2b476cd35fd8c5482c9f3aabfe27e155729b657b369493d19` |

**`event_01_gift` package** — `0xd1ed457cb4f1bb209c09a094f772472db15c115a29eb5995b7cb2a2313227896`

| Shared object | ID                                                                   |
|---------------|----------------------------------------------------------------------|
| `MintCounter` | `0x7c15f5391cd1baf53bc3280ac3f75331c5abe027a370eedb39ac9d7f301890a9` |

**Governance multisig (2/3)** — `0xd86de144b080a31394c7d5506ecff077196da2a30f6e8aab1637d2cee2f0fb0d`
holds both `UpgradeCap`s, `chronicle::AdminCap`, `event_01_gift::GiftAdminCap`,
and all `Publisher` objects. `Display` objects remain in an operational wallet.

## Build & test

Requires the [Sui CLI](https://docs.sui.io/references/cli) (toolchain 1.64+).

```bash
cd sui/chronicle     && sui move build && sui move test   # 12 tests
cd sui/event_01_gift && sui move build && sui move test   #  6 tests
```

## Deploy

Publish order is `chronicle` first, then `event_01_gift` (the latter depends on
the former). After publishing, set the voucher authority key with
`set_authority_pubkey` and transfer the capabilities to the multisig. The full
mainnet + multisig runbook lives in `../docs/deploy/` (private).

## Conventions

- **Public repo.** No real-person names, keys, mnemonics, or team-internal docs
  (those live in `../docs/`, private). See `.gitignore` for blocked
  keystore / `.env` / wallet patterns.
- **`Published.toml` is the source of truth** for deployed addresses; consumers
  read IDs from config, never hand-edited into source.
- Move edition `2024.beta`; framework pinned to `framework/mainnet`.
