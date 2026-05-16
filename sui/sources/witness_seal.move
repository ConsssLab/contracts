// Module: chronicle::witness_seal
//
// The Validators' Witness — a soulbound NFT minted by Battle 3 victors to
// commemorate the historic 90.9% validator vote at Crystal Sanctum.
//
// ============================================================================
// SOULBOUND DESIGN
// ----------------------------------------------------------------------------
// `WitnessSeal` is declared with `key` only — NO `store` ability. In Sui Move
// 2024, only objects that have `store` can be moved by `transfer::public_*`
// or wrapped/unwrapped by user code. By withholding `store` and exposing no
// transfer entry function, this module makes the WitnessSeal effectively
// non-transferable after `transfer::transfer` lands it in the player's
// account at mint time.
//
//   - The struct has `key` (so it can be an object).
//   - The struct does NOT have `store` (so no public_transfer is possible).
//   - This module exposes no transfer / send / give-away function.
//   - One-per-player is enforced via the WitnessRegistry table.
//
// Result: once minted, a WitnessSeal cannot leave its owner's address.
// ============================================================================

module chronicle::witness_seal;

use std::string::{Self, String};
use sui::clock::{Self, Clock};
use sui::display;
use sui::event;
use sui::package;
use sui::table::{Self, Table};

// ---------- Errors ----------

const EInvalidBattle: u64 = 1;
const EAlreadyMinted: u64 = 2;
const ETitleTooLong: u64 = 3;
const EInscriptionTooLong: u64 = 4;
const ETitleEmpty: u64 = 5;
const EInvalidHeroId: u64 = 6;
const EInvalidRating: u64 = 7;

// ---------- Constants ----------

const WITNESS_BATTLE_ID: u8 = 3;
// Title / inscription are validated in bytes; CJK characters take 3-4 bytes
// in UTF-8, so a 50-character (zh-TW) inscription needs ~200 bytes.
const MAX_TITLE_LEN: u64 = 320;
const MAX_INSCRIPTION_LEN: u64 = 200;
const MAX_HERO_ID: u8 = 20;
const MAX_RATING: u8 = 3;

// ---------- One-time witness for Display ----------

public struct WITNESS_SEAL has drop {}

// ---------- Types ----------

/// Shared registry: tracks which players have already claimed their seal,
/// and the running mint_order for Battle 3 witnesses.
public struct WitnessRegistry has key {
    id: UID,
    /// Players who have minted (one-per-player enforcement).
    minted: Table<address, bool>,
    /// Number of seals minted so far.
    total_minted: u64,
}

/// Soulbound Validators' Witness. NOTE: NO `store` ability — see header.
public struct WitnessSeal has key {
    id: UID,
    battle_id: u8,
    hero_id: u8,
    title: String,
    inscription: String,
    rating: u8,
    mint_order: u64,
    is_first_chronicler: bool,
    /// Sui consensus timestamp (ms) at mint time. See chronicle.move for why
    /// this is preferable to "block height" on Sui.
    mint_timestamp_ms: u64,
    player: address,
}

// ---------- Events ----------

public struct WitnessSealMinted has copy, drop {
    seal_id: ID,
    player: address,
    mint_order: u64,
    is_first: bool,
}

// ---------- init ----------

fun init(otw: WITNESS_SEAL, ctx: &mut TxContext) {
    // Publisher object enables Display registration.
    let publisher = package::claim(otw, ctx);

    let keys = vector[
        string::utf8(b"name"),
        string::utf8(b"description"),
        string::utf8(b"image_url"),
        string::utf8(b"project_url"),
        string::utf8(b"creator"),
    ];
    let values = vector[
        string::utf8(b"Validators' Witness — {title}"),
        string::utf8(
            b"Soulbound. Cannot be transferred. Witness to the historic 90.9% validator vote at Crystal Sanctum, the night Suiren refused to fall.",
        ),
        string::utf8(b"https://chainoa.consss.io/witness/{id}.png"),
        string::utf8(b"https://chainoa.consss.io"),
        string::utf8(b"ConsssLabs"),
    ];

    let mut display = display::new_with_fields<WitnessSeal>(
        &publisher,
        keys,
        values,
        ctx,
    );
    display::update_version(&mut display);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(display, tx_context::sender(ctx));

    let registry = WitnessRegistry {
        id: object::new(ctx),
        minted: table::new<address, bool>(ctx),
        total_minted: 0,
    };
    transfer::share_object(registry);
}

// ---------- Mint ----------

/// Mint a Validators' Witness seal for the calling player.
///
/// Constraints:
///   - `battle_id` MUST equal 3 (Crystal Sanctum).
///   - The caller must not have minted before.
///
/// NOTE: This entry does not itself check that the player completed Battle 3
/// — that proof of completion is enforced off-chain by the game client +
/// signature flow. (A future revision could require a Chronicle reference,
/// but that couples the modules in a way W6 doesn't want.)
public entry fun mint_witness(
    registry: &mut WitnessRegistry,
    battle_id: u8,
    hero_id: u8,
    title: vector<u8>,
    inscription: vector<u8>,
    rating: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(battle_id == WITNESS_BATTLE_ID, EInvalidBattle);
    assert!(hero_id >= 1 && hero_id <= MAX_HERO_ID, EInvalidHeroId);
    assert!(rating <= MAX_RATING, EInvalidRating);

    let title_len = vector::length(&title);
    assert!(title_len > 0, ETitleEmpty);
    assert!(title_len <= MAX_TITLE_LEN, ETitleTooLong);
    assert!(vector::length(&inscription) <= MAX_INSCRIPTION_LEN, EInscriptionTooLong);

    let player = tx_context::sender(ctx);
    assert!(!table::contains(&registry.minted, player), EAlreadyMinted);

    table::add(&mut registry.minted, player, true);
    registry.total_minted = registry.total_minted + 1;
    let next_order = registry.total_minted;

    let seal = WitnessSeal {
        id: object::new(ctx),
        battle_id,
        hero_id,
        title: string::utf8(title),
        inscription: string::utf8(inscription),
        rating,
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        player,
    };

    let seal_id = object::id(&seal);

    event::emit(WitnessSealMinted {
        seal_id,
        player,
        mint_order: next_order,
        is_first: next_order == 1,
    });

    // `transfer::transfer` works on objects with `key` only; this is the only
    // way a key-only object can move. After this, no public_transfer path
    // exists, locking the seal to `player`.
    transfer::transfer(seal, player);
}

// ---------- Read accessors ----------

public fun battle_id(s: &WitnessSeal): u8 { s.battle_id }
public fun hero_id(s: &WitnessSeal): u8 { s.hero_id }
public fun title(s: &WitnessSeal): &String { &s.title }
public fun inscription(s: &WitnessSeal): &String { &s.inscription }
public fun rating(s: &WitnessSeal): u8 { s.rating }
public fun mint_order(s: &WitnessSeal): u64 { s.mint_order }
public fun is_first_chronicler(s: &WitnessSeal): bool { s.is_first_chronicler }
public fun mint_timestamp_ms(s: &WitnessSeal): u64 { s.mint_timestamp_ms }
public fun player(s: &WitnessSeal): address { s.player }

public fun has_minted(registry: &WitnessRegistry, who: address): bool {
    table::contains(&registry.minted, who)
}

public fun total_minted(registry: &WitnessRegistry): u64 {
    registry.total_minted
}

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let registry = WitnessRegistry {
        id: object::new(ctx),
        minted: table::new<address, bool>(ctx),
        total_minted: 0,
    };
    transfer::share_object(registry);
}
