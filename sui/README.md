# Sui Move packages

Two packages — see the repo root [`../README.md`](../README.md) for the full
overview (anti-cheat voucher model, governance, mainnet addresses).

- [`chronicle/`](./chronicle) — package `chronicle`, with modules `chronicle`
  (transferable, tiered per-battle **Chronicle** NFT) and `echoes_of_chainoa`
  (soulbound **Finale Badge**). Publish this first.
- [`event_01_gift/`](./event_01_gift) — the one-per-wallet limited-time
  **"1st Gift"**; depends on `chronicle`.

## Build & test

```bash
cd chronicle     && sui move build && sui move test   # 12 tests
cd event_01_gift && sui move build && sui move test   #  6 tests
```

`Published.toml` (committed, per package) is the source of truth for deployed
addresses; `Move.lock` is toolchain-local.
