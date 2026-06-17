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

## Live IDs

| Object | testnet (deployed 2026-06-17) | mainnet |
|---|---|---|
| package | `0x36cc746e0943c81853b1f7584c78328bf97a3c2a344033c21af8265db25a3374` | — |
| `SovereignRegistry` | `0x60db6d46359cd0d5e08f5aa4e87504a5751148f3d18af5f153435f260e8b244f` | — |
| `AdminCap` | `0xff90503c628d977c8cbca0ce730cd947c7cc570bc1100d1300a7f8f04cf194b5` | — |
| `UpgradeCap` | `0x8d153e05bf63b6bdad9fbd043f0dc2080a8319129995390c1a89a7662e086293` (dev key) | — |
| `Publisher` | `0x40b3b6768389499c90e02578bf201e9d46f773287e88d11e65f57e9fd19982c2` | — |

Deployer/owner of the caps: `0x9550…8049` (ops). Authority pubkey
`06e336…57dd` set via `set_authority_pubkey`. Testnet uses no multisig (caps on
the dev key); move to multisig at mainnet.

Display `image_url` templates to
`https://conssslab.github.io/public-assets/sovereign/battle-{battle_id}-{tier}.png`
— add those art files to `public-assets` (battle 1..3 × tier 0..3).
