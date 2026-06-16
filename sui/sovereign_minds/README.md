# sovereign_minds — ConSSS Wars: Sovereign Minds (群雄覺醒) contract

A **standalone** Move package for the Sovereign Minds installment. It is
deliberately **not** an upgrade of `chronicle` (Echoes of Chainoa):

- Its `UpgradeCap` stays on a **dev key** during the sprint and moves to the 2/3
  multisig only at launch → fast iteration, no multisig ceremony per redeploy.
- A bug here can never touch the live Echoes mainnet NFTs.
- It ships the `version` gate from v1 (Echoes' early modules lacked it).
- Clean home to later add **TEE/Nautilus attestation verification** via upgrade.

## What it does

`sovereign::mint_deed` mints a transferable **SovereignDeed** NFT after a cleared
water-chapter battle. The mint is gated by an **ed25519 voucher** signed by the
off-chain authority — but unlike Echoes, the voucher attests a **server-computed
score `score_milli` (z × 1000)**, not a client-reported HP. See
`docs/sovereign-minds/anti-cheat-protocol.md`.

- Voucher: domain `ConSSSWars/sovereign-voucher/v1`, registry-bound, one-time
  nonce, expiry vs on-chain clock. Byte layout in the module header.
- Tier: floor by per-battle mint rank (Silver ≤100, Bronze ≤300, Normal ≤1000,
  none at 1001+), upgrade one step if `hp ≥ 80` **or** `score ≥ threshold`
  (admin-tunable; default off so it's HP-only until tuned).
- Same hardening as chronicle: `version` gate, `paused` kill-switch, admin caps,
  configurable `max_battle_id` / `max_hero_id`.

## Build & test

```bash
sui move build
sui move test     # incl. voucher_crossvalidation_matches_offchain_signer
```

The crossvalidation test proves the on-chain `build_voucher_message` is
byte-identical to the off-chain signer (`play/shared/voucher.mjs`). Regenerate
its fixed (pubkey, sig) vector with `cd play && node shared/selftest.mjs`.

## Deploy (testnet first)

```bash
sui client switch --env testnet
sui client publish --gas-budget 200000000
```

Then, as the `AdminCap` holder, wire the authority pubkey printed by
`node play/scripts/gen-authority-key.mjs`:

```bash
sui client call --package <PKG> --module sovereign \
  --function set_authority_pubkey \
  --args <ADMIN_CAP_ID> <SOVEREIGN_REGISTRY_ID> "[<32 pubkey bytes>]"
```

## Live IDs (fill after deploy)

| Object | testnet | mainnet |
|---|---|---|
| package | `0x…` | — |
| `SovereignRegistry` | `0x…` | — |
| `AdminCap` | `0x…` | — |
| `UpgradeCap` | `0x…` (dev key) | — |
| `Publisher` / `Display` | `0x…` | — |

Display `image_url` templates to
`https://conssslab.github.io/public-assets/sovereign/battle-{battle_id}-{tier}.png`
— add those art files to `public-assets` (battle 1..3 × tier 0..3).
