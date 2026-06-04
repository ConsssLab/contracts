# Chronicle — Sui Move package

Two modules:

- `chronicle::chronicle` — transferable Chronicle NFT minted after every battle.
  A shared `ChronicleRegistry` keeps a per-`battle_id` counter so each NFT
  records which numbered chronicler the player is.
- `chronicle::witness_seal` — **soulbound** Validators' Witness, mint-once-per-
  player and only for Battle 3. The struct intentionally omits the `store`
  ability and exposes no transfer entry function.

## Build

```bash
sui move build
```

## Test

```bash
sui move test
```

## Publish (testnet)

```bash
sui client publish --gas-budget 200000000
```

After publish, capture:
- `PACKAGE_ID`
- `ChronicleRegistry` shared object id
- `WitnessRegistry` shared object id

The init functions create both registries as shared objects automatically.

## Display metadata

Chronicle uses `sui::display` so wallets render per-tier art at
`https://conssslab.github.io/public-assets/chronicle/battle-{battle_id}-{tier}.png`.
The Display object is held by the deployer and can be updated without a package
upgrade.
