# Sui Contracts — Pre-deploy Review (W1)

Reviewed against `docs/SPEC.md` v3.1 + `docs/business/model.md` v1.0.

**Status (2026-05-16)**: All three W6-blocking issues are now resolved.
`sui move test` reports **12/12 tests passing**. Contracts are ready for the
W6 testnet `sui client publish` step.

**Overall**: solid foundation, ships ~95% of W6 requirements. Three issues
identified at W1 review; all fixed below.

## ✅ What works

| Requirement (SPEC) | Implementation | Status |
|---|---|---|
| Chronicle NFT transferable | `Chronicle has key, store` | ✅ |
| Witness Seal soulbound | `WitnessSeal has key` (no `store`); no transfer fn exposed | ✅ — clean technique |
| Per-battle mint counter | `ChronicleRegistry.counts: Table<u8, u64>` | ✅ |
| First-chronicler flag | `is_first_chronicler = next_order == 1` | ✅ |
| Witness Seal one-per-player | `WitnessRegistry.minted: Table<address, bool>` | ✅ |
| Battle 3 only for seal | `assert!(battle_id == WITNESS_BATTLE_ID, …)` | ✅ |
| Sui Display registered | `display::new_with_fields<Chronicle>(…)` | ✅ for Chronicle |
| `mint_chronicle` events | `ChronicleMinted` w/ chronicle_id, player, battle_id, mint_order, is_first | ✅ |
| Gas-only mint (no fee) | No coin payment in entry signatures | ✅ |
| Title / inscription bounds | `MAX_TITLE_LEN=80`, `MAX_INSCRIPTION_LEN=50` | ⚠️ (see issue 1) |

## ✅ Issues fixed during W1 review (all resolved)

### 1. Inscription length is byte-limited, not character-limited (real bug) — **FIXED**

**SPEC** (`business/model.md` §2): "玩家寫的 50 字題辭" — 50 Chinese characters.

**Code**: `MAX_INSCRIPTION_LEN: u64 = 50` and
```move
assert!(vector::length(&inscription) <= MAX_INSCRIPTION_LEN, EInscriptionTooLong);
```
`vector::length` over a `vector<u8>` counts **bytes**. UTF-8 CJK characters
are 3 bytes each, so a Chinese player gets ~16 characters before the contract
rejects, not 50.

**Fix options**:
- (a) Raise `MAX_INSCRIPTION_LEN` to **200** (≈ 50 CJK × 4-byte upper bound, or 200 ASCII).
- (b) Do char-counting in Move (expensive, fiddly — not recommended).
- (c) Enforce in the client only (drop the on-chain assert). Bad — clients lie.

**Fix applied**: bumped `MAX_INSCRIPTION_LEN` 50→200 and `MAX_TITLE_LEN`
80→320 in both modules; tests updated to assert against new byte ceilings.

### 2. `block_height_at_mint` is misnamed — stores a ms timestamp — **FIXED**

```move
block_height_at_mint: clock::timestamp_ms(clock),
```
`Clock::timestamp_ms` returns the Sui consensus timestamp in **milliseconds**,
not a block height. Sui doesn't have block heights in the EVM sense — its
closest equivalents are **checkpoint sequence number** (per-checkpoint) and
**epoch** (~24h epochs).

**Why it matters**: the field is included in the NFT and exposed via
accessor; downstream code, indexers, and our own UI will read the name
literally and display a multi-billion timestamp as if it were a block height.

**Fix options**:
- (a) Rename field → `mint_timestamp_ms` and update SPEC `business/model.md`
  ("鑄造時的 Sui 區塊高度" → "鑄造時的 Sui 時間戳") + accessor name.
- (b) Switch source to `tx_context::epoch(ctx)` for a coarser but accurate
  "Sui epoch at mint" and rename to `mint_epoch`.

**Fix applied**: renamed field + accessor to `mint_timestamp_ms` in both
modules; doc comment explains "Sui has no block height; this + tx digest are
the time anchors." Updated `docs/business/model.md` description accordingly.

### 3. WitnessSeal has no `Display` registered — **FIXED**

Wallets (Slush, Sui Wallet) and explorers (SuiVision, SuiScan) use `Display`
to render NFTs. Without it, the Validators' Witness shows up as a raw object
with no thumbnail or description.

For an NFT whose **explicit design goal** is "圈內人會主動截圖發推, 病毒擴散的核心"
(`model.md` §2), missing Display defeats the marketing intent.

**Fix**: add a Display block in `witness_seal::init` mirroring chronicle's,
with a soulbound-specific description ("Cannot be transferred. Witness to
the 90.9% vote at Crystal Sanctum, 2025-05.").

**Fix applied**: added `WITNESS_SEAL` OTW + `package::claim` +
`display::new_with_fields` block in `witness_seal::init`. Display description
emphasises soulbound nature ("Cannot be transferred. Witness to the historic
90.9% validator vote at Crystal Sanctum.").

### Bonus fix (uncovered during validation)

`#[expected_failure(abort_code = ...)]` annotations in tests used
`chronicle::chronicle::EXxx` (full package-qualified path), which Sui CLI
1.64.1 rejects with `E10003: invalid attribute value` — it expects a u64
literal or `module::const` form. Updated to `chronicle::EXxx` /
`witness_seal::EXxx`. All 12 tests now pass.

## 🟡 Acceptable for MVP / hackathon (not bugs)

- **No on-chain proof of Battle 3 completion** for `mint_witness`. Comment
  in source acknowledges this; off-chain client + signature flow handles it.
  Fine for MVP — coupling to `Chronicle` would also create a circular
  reference between modules.
- **`MAX_HERO_ID=20`** is generous (Sui chapter only uses 1..=5). Loose, not
  wrong — keeps later chapter DLCs unblocked.
- **No event-by-battle indexing accessor** — fine, this is what off-chain
  indexers (or `suix_queryEvents` filters) are for.
- **`Move.toml` pins `framework/testnet`**: correct for W6 testnet deploy.
  When we go mainnet (post-MVP), pin to a specific commit hash for
  reproducibility.

## 🟢 Stylistic notes (don't bother)

- Error codes are sparse (`u64`) and don't follow a namespacing convention,
  but Move tooling reports them by name not number, so fine.
- `count_for_battle` returning `0` on missing key is friendly; consistent
  with idiomatic Sui Move.
- Test coverage in `chronicle_tests.move` / `witness_seal_tests.move` looks
  reasonable — first-mint, second-mint, soulbound-cannot-transfer paths
  covered.

## Remaining action items for W6 sprint

(Issues 1-3 plus the bonus test-attribute fix are done.)

1. ~~Bump byte limits~~ — done.
2. ~~Rename `block_height_at_mint` → `mint_timestamp_ms`~~ — done.
3. ~~Add `Display` to `WitnessSeal`~~ — done.
4. ~~Re-run `sui move test`~~ — done: 12/12 PASS.
5. **TODO (W6)**: `sui client publish` to testnet, record package ID in
   `app/godot/scripts/web3/sui_wallet_bridge.gd` plus a `data/web3.tres`
   config resource.
6. **TODO (W6)**: replace placeholder image URLs (`https://chainoa.consss.io/chronicle/{id}.png`
   and `.../witness/{id}.png`) once art is generated. Art lands W7-W8 per
   `docs/erwin-asset-spec.md`.
