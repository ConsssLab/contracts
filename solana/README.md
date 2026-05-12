# Solana program (skeleton — flesh out in W8)

Anchor 0.30.x program named `chronicle`. Stores per-mint Chronicle data in a
PDA derived from `(player, battle_id, mint_order)`.

## What's here

- `programs/chronicle/src/lib.rs` — single `mint_chronicle` instruction +
  `BattleCounter` PDA per battle.
- Validation mirrors the Sui Move module (battle 1..3, hero 1..20, rating
  0..3, title <= 80 bytes, inscription <= 50 bytes).

## Not here yet (W8)

- **Metaplex Token Metadata integration** is a W8 task. The current skeleton
  stores metadata on-chain in the PDA only.
- Soulbound `WitnessSeal` port. The simplest Solana approach is a non-
  transferable mint via the SPL Token-2022 `NonTransferable` extension; that
  decision is W8.

## Build / test

```bash
anchor build
anchor test
```

The placeholder program ID `Chronic1eProgram1111111111111111111111111111`
must be replaced after the first `anchor keys list` run.
