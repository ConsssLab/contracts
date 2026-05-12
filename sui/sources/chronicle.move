// Module: chronicle::chronicle
//
// Transferable Chronicle NFT minted by a player after completing a battle.
// Each mint increments a per-battle counter held in the shared ChronicleRegistry,
// so every NFT carries its position in the global ranking ("you are the Nth
// chronicler of this battle"). The first chronicler of a given battle is
// flagged with `is_first_chronicler = true` and rendered with a special
// border in-game.
//
// This NFT is freely transferable (key + store). For the soulbound
// Validators' Witness see `chronicle::witness_seal`.

module chronicle::chronicle;

use std::string::{Self, String};
use sui::clock::{Self, Clock};
use sui::display;
use sui::event;
use sui::package;
use sui::table::{Self, Table};

// ---------- Errors ----------

const ETitleTooLong: u64 = 1;
const EInscriptionTooLong: u64 = 2;
const EInvalidBattleId: u64 = 3;
const EInvalidHeroId: u64 = 4;
const EInvalidRating: u64 = 5;
const ETitleEmpty: u64 = 6;

// ---------- Constants ----------

const MAX_TITLE_LEN: u64 = 80;
const MAX_INSCRIPTION_LEN: u64 = 50;
// MVP ships 3 battles; future chapters can bump this constant.
const MAX_BATTLE_ID: u8 = 3;
// Hero IDs roughly follow the Suiren roster: 1=Lyric, 2=Tidea, 3=Swift,
// 4=Aedric, 5=Cypher. Reserve 1..=20 for future chapters.
const MAX_HERO_ID: u8 = 20;
// Rating: 0=Decisive, 1=Victory, 2=Narrow, 3=Pyrrhic.
const MAX_RATING: u8 = 3;

// ---------- One-time witness for Display ----------

public struct CHRONICLE has drop {}

// ---------- Types ----------

/// Shared registry tracking per-battle mint order.
public struct ChronicleRegistry has key {
    id: UID,
    /// battle_id -> count of chronicles minted for that battle so far.
    counts: Table<u8, u64>,
}

/// Transferable Chronicle NFT.
public struct Chronicle has key, store {
    id: UID,
    battle_id: u8,
    hero_id: u8,
    title: String,
    inscription: String,
    rating: u8,
    mint_order: u64,
    is_first_chronicler: bool,
    block_height_at_mint: u64,
    player: address,
}

// ---------- Events ----------

public struct ChronicleMinted has copy, drop {
    chronicle_id: ID,
    player: address,
    battle_id: u8,
    mint_order: u64,
    is_first: bool,
}

// ---------- init ----------

fun init(otw: CHRONICLE, ctx: &mut TxContext) {
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
        string::utf8(b"{title}"),
        string::utf8(
            b"A Chronicle of the Chainoa Eternal Chronicles. Battle {battle_id}, written by chronicler #{mint_order}.",
        ),
        string::utf8(b"https://chainoa.consss.io/chronicle/{id}.png"),
        string::utf8(b"https://chainoa.consss.io"),
        string::utf8(b"ConsssLabs"),
    ];

    let mut display = display::new_with_fields<Chronicle>(
        &publisher,
        keys,
        values,
        ctx,
    );
    display::update_version(&mut display);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(display, tx_context::sender(ctx));

    // Create and share the registry so any player can mint via it.
    let registry = ChronicleRegistry {
        id: object::new(ctx),
        counts: table::new<u8, u64>(ctx),
    };
    transfer::share_object(registry);
}

// ---------- Mint ----------

/// Mint a Chronicle NFT for the calling player. Validates field lengths,
/// increments the per-battle counter, and emits ChronicleMinted.
public entry fun mint_chronicle(
    registry: &mut ChronicleRegistry,
    battle_id: u8,
    hero_id: u8,
    title: vector<u8>,
    inscription: vector<u8>,
    rating: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // ---- validate ----
    assert!(battle_id >= 1 && battle_id <= MAX_BATTLE_ID, EInvalidBattleId);
    assert!(hero_id >= 1 && hero_id <= MAX_HERO_ID, EInvalidHeroId);
    assert!(rating <= MAX_RATING, EInvalidRating);

    let title_len = vector::length(&title);
    assert!(title_len > 0, ETitleEmpty);
    assert!(title_len <= MAX_TITLE_LEN, ETitleTooLong);
    assert!(vector::length(&inscription) <= MAX_INSCRIPTION_LEN, EInscriptionTooLong);

    // ---- bump counter ----
    let next_order = if (table::contains(&registry.counts, battle_id)) {
        let prev = table::borrow_mut(&mut registry.counts, battle_id);
        *prev = *prev + 1;
        *prev
    } else {
        table::add(&mut registry.counts, battle_id, 1);
        1
    };

    let player = tx_context::sender(ctx);
    let nft = Chronicle {
        id: object::new(ctx),
        battle_id,
        hero_id,
        title: string::utf8(title),
        inscription: string::utf8(inscription),
        rating,
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        block_height_at_mint: clock::timestamp_ms(clock),
        player,
    };

    let chronicle_id = object::id(&nft);

    event::emit(ChronicleMinted {
        chronicle_id,
        player,
        battle_id,
        mint_order: next_order,
        is_first: next_order == 1,
    });

    transfer::public_transfer(nft, player);
}

// ---------- Read accessors ----------

public fun battle_id(c: &Chronicle): u8 { c.battle_id }
public fun hero_id(c: &Chronicle): u8 { c.hero_id }
public fun title(c: &Chronicle): &String { &c.title }
public fun inscription(c: &Chronicle): &String { &c.inscription }
public fun rating(c: &Chronicle): u8 { c.rating }
public fun mint_order(c: &Chronicle): u64 { c.mint_order }
public fun is_first_chronicler(c: &Chronicle): bool { c.is_first_chronicler }
public fun block_height_at_mint(c: &Chronicle): u64 { c.block_height_at_mint }
public fun player(c: &Chronicle): address { c.player }

public fun count_for_battle(registry: &ChronicleRegistry, battle_id: u8): u64 {
    if (table::contains(&registry.counts, battle_id)) {
        *table::borrow(&registry.counts, battle_id)
    } else {
        0
    }
}

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let registry = ChronicleRegistry {
        id: object::new(ctx),
        counts: table::new<u8, u64>(ctx),
    };
    transfer::share_object(registry);
}
