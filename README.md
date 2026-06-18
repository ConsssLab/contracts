# ConSSS Wars Contracts

[![Sui Mainnet](https://img.shields.io/badge/Sui-Mainnet-4DA2FF?logo=sui&logoColor=white)](https://suiscan.xyz/mainnet)

On-chain contracts for **ConSSS Wars: Echoes of Chainoa（鏈州英雄傳：鏈之迴響）**, a
turn-based tactical RPG. Players mint a **Chronicle** NFT after each battle, a
soulbound **Finale Badge** for clearing the climax, and a one-per-wallet
limited-time **Gift** for completing the campaign. Sui is the primary chain.

> **No token. No presale. No airdrop.** Minting is gas-only — the team takes no
> cut. The contracts hold **no funds** (no `Coin`/`Balance` anywhere), so there
> is nothing to drain. Game design and operational runbooks live in a separate
> private repo (`../docs/`).

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

## Modules

Three Move modules across two published packages:

| Module | Package | Purpose |
|--------|---------|---------|
| `chronicle::chronicle` | `chronicle` (`0x5760b2685d41bd45e2991dedc242e866b1aca9ff3c3a5e193445751c2b8dfe4b`) | Transferable, on-chain-tiered per-battle **Chronicle** NFT (Normal / Bronze / Silver / Gold by clear-rank + HP). |
| `chronicle::echoes_of_chainoa` | `chronicle` (same package) | **Soulbound** Finale Badge for clearing the climax (Battle 3); `key`-only, no transfer. |
| `event_01_gift::event_01_gift` | `event_01_gift` (`0xd1ed457cb4f1bb209c09a094f772472db15c115a29eb5995b7cb2a2313227896`) | One-per-wallet limited-time **"1st Gift"**, gated by holding the Chronicles the wallet earned for battles 1 / 2 / 3. |

`event_01_gift` reads `Chronicle` ownership at mint, so it depends on the
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
minted. One per player, enforced by the shared `FinaleRegistry`. The module
fixes its battle (`FINALE_BATTLE_ID = 3`) forever; future installments ship their
own finale module rather than mutating this one.

### `event_01_gift::event_01_gift` — limited-time event

A wallet may mint exactly one Gift, only while the event is open (on-chain
`end_ms` deadline), and only by passing three `&Chronicle` it **earned itself**
(each Chronicle's `player` field must equal the caller) covering three distinct
battles within `{1, 2, 3}`. Binding to `player` blocks claiming with frozen or
transferred-in Chronicles. The numbered name (`event_01_…`) reserves the
namespace for future events.

## Data-structure design

Three shared registries track all mutable state; the three NFT structs carry only
immutable per-item data. Field names below are exactly as defined in the modules.

### Shared registries

| Registry (shared object) | Module | Key fields |
|--------------------------|--------|------------|
| `ChronicleRegistry` | `chronicle` | `counts: Table<u8, u64>` (per-battle mint order), `used_nonces: Table<u64, bool>` (voucher replay protection), `authority_pubkey`, admin-configurable `max_battle_id` / `max_hero_id`, `version`, `paused` |
| `FinaleRegistry` | `echoes_of_chainoa` | `minted: Table<address, bool>` (one-per-player), `total_minted`, `authority_pubkey`, `used_nonces: Table<u64, bool>`, `version`, `paused` |
| `MintCounter` | `event_01_gift` | `claimed: Table<address, bool>` (one-per-wallet), `minted`, `end_ms` (deadline), `version`, `paused` |

### NFT structs

| Struct | Abilities | Transferability |
|--------|-----------|-----------------|
| `Chronicle` | `key, store` | Transferable keepsake |
| `FinaleBadge` | `key` only | **Soulbound** (no `store`, no transfer entry) |
| `Gift` | `key, store` | Transferable reward |

## Capability design

Every governance action is gated by an explicit capability object; every
player-facing entry function is gated by a version check (`VERSION` /
`assert_active` / `migrate`) **plus** a `paused` kill-switch. The package
deliberately **merges** the two NFT admins in the `chronicle` package under one
cap so the whole package is governed by a single key, and keeps the gift event's
admin separate so its governance can be burned independently once the event ends.

| Capability  | Count | Holder | Purpose |
|-------------|-------|--------|---------|
| `chronicle::AdminCap` | 1 (merged) | 2/3 multisig (cold) | Single admin for **both** `chronicle` and `echoes_of_chainoa`: rotate the voucher authority pubkey, pause, set `max_battle_id` / `max_hero_id`, migrate after upgrade |
| `event_01_gift::GiftAdminCap` | 1 | 2/3 multisig (cold) | Pause, set event deadline `end_ms`, migrate, and `burn_admin_cap` to retire governance after the event |
| `UpgradeCap` | 2 (one per package) | 2/3 multisig (cold) | Package upgrades |
| `Publisher` | 3 (one per module) | 2/3 multisig (cold) | `Display` administration only |
| `Display` | 3 (one per NFT type) | operational wallet (hot) | NFT art metadata; updating it can't mint, upgrade, or steal |

The `echoes_of_chainoa` module imports and reuses `chronicle::AdminCap` rather
than defining its own — one cap, one package, no second key to protect.

## Multisig

All governance capabilities — `UpgradeCap` ×2, `chronicle::AdminCap`,
`event_01_gift::GiftAdminCap`, and `Publisher` ×3 — are held by a **2-of-3
multisig** (`0xd86de144b080a31394c7d5506ecff077196da2a30f6e8aab1637d2cee2f0fb0d`)
whose keys are split across **3 separate devices**. None of these caps live on
the deployer or a developer machine. Only the `Display` objects remain in a hot
operational wallet, so routine art updates never need to touch a cap that could
mint, upgrade, or move funds.

No capability, key, mnemonic, or secret lives in this repo (see `.gitignore`).

## Security protections

- **ed25519 authority voucher (anti-cheat).** A client cannot mint by crafting a
  transaction directly. `mint_chronicle` and `mint_finale` each require a voucher
  signed by an off-chain authority key the game backend controls, attesting facts
  the client cannot forge (remaining-HP%, finale clearance). The signed message is
  a domain-prefixed BCS byte string:

  ```
  DOMAIN ++ registry_id:address(32) ++ player:address(32)
         ++ battle_id:u8 ++ hero_id:u8 ++ (hp_pct|rating):u8
         ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
  ```

  - **Domain separator** — `ConSSSWars/chronicle-voucher/v1` (and a distinct
    `ConSSSWars/finale-voucher/v1` for the badge) binds a signature to this
    contract and purpose; the two vouchers cannot be cross-used.
  - **`registry_id` binding** pins the voucher to this exact deployment — no
    cross-deployment replay, even if an authority key is ever reused elsewhere.
  - **`nonce`** (kept in `used_nonces`) blocks replay; **`expiry_ms`** checked
    against the on-chain `Clock` blocks stale reuse; the signature must be exactly
    64 bytes and the authority public key 32 bytes.

- **Gift `player == caller` binding.** The event verifies each `&Chronicle`'s
  `player` field equals the caller, defeating the frozen-/transferred-Chronicle
  bypass (a frozen Chronicle's `player` is still the original clearer, not the
  caller). Combined with the exact `{1, 2, 3}` battle-set gate and one-per-wallet
  `claimed` table, a given set can only ever yield its single owner's one claim.

- **Soulbound finale.** `FinaleBadge` has no `store` and no transfer entry, so it
  is permanently bound to the player who earned it.

- **Version gate + pause on every entry.** Each player-facing entry asserts the
  registry `version == VERSION` and `!paused`; after a package upgrade, `migrate`
  bumps the registry so old package code can no longer touch it.

- **Cold-key governance.** All caps sit in a 2/3 multisig across 3 devices (see
  above); only `Display` is hot.

- **No funds at risk.** The contracts hold no `Coin`/`Balance`, so there is
  nothing to drain even if a key were lost.

- **Cross-language byte-layout pinning.** The on-chain voucher message layout is
  pinned to the backend signer byte-for-byte by the
  `chronicle::chronicle_tests::voucher_message_byte_layout` test.

**Tests:** `chronicle` 12, `event_01_gift` 6.

### Security review

The contracts were **reviewed by automated security review (Codex + Claude) and a
multi-agent audit**. The review **found no high-confidence vulnerabilities**.
This is a review outcome, not an absolute guarantee that the code is bug-free.

## Walrus

`metadata_blob_id` is the Walrus blob ID the dApp receives after uploading the
player's Chronicle JSON (battle log, hero pose, screenshot, long text). The Move
`Display` embeds a Walrus aggregator URL template, so any wallet or indexer
resolving the Display can fetch the off-chain payload without an extra contract
call.

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
