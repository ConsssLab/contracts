// Module: chronicle::echoes_of_chainoa
//
// The soulbound finale badge for ConSSS Wars: **Echoes of Chainoa** (this
// installment). Minted by clearing the installment's climax battle (Battle 3,
// the Crystal Sanctum — the 90.9% validator vote). It commemorates a SPECIFIC
// moment, so its battle is fixed forever; future installments ship their own
// finale module (e.g. the next subtitle), not a change to this one.
//
// ============================================================================
// SOULBOUND — `FinaleBadge` has `key` only (NO `store`): no public_transfer and
// no transfer entry function, so once `transfer::transfer` lands it on the
// player it can never move. One-per-player via the registry table.
// ============================================================================
// ANTI-CHEAT — `mint_finale` requires an ed25519 voucher signed by the game
// authority key (attests Battle-3 clearance). Replay blocked by a one-time
// nonce, staleness by expiry vs the on-chain clock.
//
//   Voucher message = domain prefix ++ BCS bytes (backend must byte-match):
//     b"ConSSSWars/finale-voucher/v1" ++ player:address(32) ++ battle_id:u8
//       ++ hero_id:u8 ++ rating:u8 ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
//   Distinct domain from chronicle's, so the two vouchers can't be cross-used.
// ============================================================================

module chronicle::echoes_of_chainoa;

use std::string::{Self, String};
use std::bcs;
use sui::clock::{Self, Clock};
use sui::display;
use sui::ed25519;
use sui::event;
use sui::package;
use sui::table::{Self, Table};
// Reuse chronicle's AdminCap as the single admin capability for the package.
use chronicle::chronicle::AdminCap;

// ---------- Errors ----------

const EInvalidBattle: u64 = 1;
const EAlreadyMinted: u64 = 2;
const ETitleTooLong: u64 = 3;
const EInscriptionTooLong: u64 = 4;
const ETitleEmpty: u64 = 5;
const EInvalidHeroId: u64 = 6;
const EInvalidRating: u64 = 7;
const EAuthorityNotSet: u64 = 8;
const EVoucherExpired: u64 = 9;
const ENonceUsed: u64 = 10;
const EBadSignature: u64 = 11;
const EBadPubkey: u64 = 12;
const EWrongVersion: u64 = 13;
const EPaused: u64 = 14;
const EAlreadyMigrated: u64 = 15;
const EBadSigLen: u64 = 16;

// ---------- Constants ----------

const VERSION: u64 = 1;

/// This installment's climax battle. Fixed forever — the badge commemorates THIS
/// specific moment; future installments ship their own finale module.
const FINALE_BATTLE_ID: u8 = 3;
const MAX_TITLE_LEN: u64 = 320;
const MAX_INSCRIPTION_LEN: u64 = 200;
const MAX_HERO_ID: u8 = 20;
const MAX_RATING: u8 = 3;

const VOUCHER_DOMAIN: vector<u8> = b"ConSSSWars/finale-voucher/v1";

// ---------- One-time witness for Display ----------

public struct ECHOES_OF_CHAINOA has drop {}

// ---------- Types ----------

/// Shared registry: one-per-player tracking, mint_order, voucher authority,
/// used nonces, version/pause gate.
public struct FinaleRegistry has key {
    id: UID,
    version: u64,
    paused: bool,
    /// Players who have minted (one-per-player enforcement).
    minted: Table<address, bool>,
    total_minted: u64,
    /// ed25519 public key (32 bytes) of the off-chain voucher signer.
    authority_pubkey: vector<u8>,
    used_nonces: Table<u64, bool>,
}

/// Soulbound finale badge. NOTE: NO `store` ability — see header.
public struct FinaleBadge has key {
    id: UID,
    battle_id: u8,
    hero_id: u8,
    title: String,
    inscription: String,
    rating: u8,
    mint_order: u64,
    is_first_chronicler: bool,
    mint_timestamp_ms: u64,
    player: address,
}

// ---------- Events ----------

public struct FinaleBadgeMinted has copy, drop {
    badge_id: ID,
    player: address,
    mint_order: u64,
    is_first: bool,
}

// ---------- init ----------

fun init(otw: ECHOES_OF_CHAINOA, ctx: &mut TxContext) {
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
        string::utf8(b"https://conssslab.github.io/public-assets/witness/seal.png"),
        string::utf8(b"https://conssswars.com"),
        string::utf8(b"ConsssLab"),
    ];

    let mut display = display::new_with_fields<FinaleBadge>(&publisher, keys, values, ctx);
    display::update_version(&mut display);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(display, tx_context::sender(ctx));

    // Admin uses chronicle::AdminCap (created in chronicle's init) — ONE cap for
    // the whole package controls both chronicle and finale admin.

    let registry = FinaleRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        minted: table::new<address, bool>(ctx),
        total_minted: 0,
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    };
    transfer::share_object(registry);
}

// ---------- Admin ----------

public entry fun set_authority_pubkey(
    _admin: &AdminCap,
    registry: &mut FinaleRegistry,
    pubkey: vector<u8>,
) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(vector::length(&pubkey) == 32, EBadPubkey);
    registry.authority_pubkey = pubkey;
}

public entry fun set_paused(_admin: &AdminCap, registry: &mut FinaleRegistry, paused: bool) {
    assert!(registry.version == VERSION, EWrongVersion);
    registry.paused = paused;
}

public entry fun migrate(_admin: &AdminCap, registry: &mut FinaleRegistry) {
    assert!(registry.version < VERSION, EAlreadyMigrated);
    registry.version = VERSION;
}

fun assert_active(registry: &FinaleRegistry) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(!registry.paused, EPaused);
}

// ---------- Mint ----------

/// Mint the soulbound finale badge for the calling player. Requires a valid
/// authority voucher attesting clearance of the climax battle.
public entry fun mint_finale(
    registry: &mut FinaleRegistry,
    battle_id: u8,
    hero_id: u8,
    title: vector<u8>,
    inscription: vector<u8>,
    rating: u8,
    nonce: u64,
    expiry_ms: u64,
    signature: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_active(registry);

    assert!(battle_id == FINALE_BATTLE_ID, EInvalidBattle);
    assert!(hero_id >= 1 && hero_id <= MAX_HERO_ID, EInvalidHeroId);
    assert!(rating <= MAX_RATING, EInvalidRating);

    let title_len = vector::length(&title);
    assert!(title_len > 0, ETitleEmpty);
    assert!(title_len <= MAX_TITLE_LEN, ETitleTooLong);
    assert!(vector::length(&inscription) <= MAX_INSCRIPTION_LEN, EInscriptionTooLong);

    let player = tx_context::sender(ctx);
    assert!(!table::contains(&registry.minted, player), EAlreadyMinted);

    // ---- verify voucher (anti-cheat) ----
    assert!(vector::length(&registry.authority_pubkey) == 32, EAuthorityNotSet);
    assert!(clock::timestamp_ms(clock) <= expiry_ms, EVoucherExpired);
    assert!(!table::contains(&registry.used_nonces, nonce), ENonceUsed);
    assert!(vector::length(&signature) == 64, EBadSigLen);
    let msg = build_voucher_message(player, battle_id, hero_id, rating, nonce, expiry_ms);
    assert!(ed25519::ed25519_verify(&signature, &registry.authority_pubkey, &msg), EBadSignature);
    table::add(&mut registry.used_nonces, nonce, true);

    // ---- mint (soulbound) ----
    table::add(&mut registry.minted, player, true);
    registry.total_minted = registry.total_minted + 1;
    let next_order = registry.total_minted;

    let badge = FinaleBadge {
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

    let badge_id = object::id(&badge);

    event::emit(FinaleBadgeMinted {
        badge_id,
        player,
        mint_order: next_order,
        is_first: next_order == 1,
    });

    // key-only object: transfer::transfer is the only move; no public_transfer
    // path exists afterward, locking the badge to `player`.
    transfer::transfer(badge, player);
}

// ---------- Internal ----------

fun build_voucher_message(
    player: address,
    battle_id: u8,
    hero_id: u8,
    rating: u8,
    nonce: u64,
    expiry_ms: u64,
): vector<u8> {
    let mut m = VOUCHER_DOMAIN;
    vector::append(&mut m, bcs::to_bytes(&player));
    vector::append(&mut m, bcs::to_bytes(&battle_id));
    vector::append(&mut m, bcs::to_bytes(&hero_id));
    vector::append(&mut m, bcs::to_bytes(&rating));
    vector::append(&mut m, bcs::to_bytes(&nonce));
    vector::append(&mut m, bcs::to_bytes(&expiry_ms));
    m
}

// ---------- Read accessors ----------

public fun battle_id(s: &FinaleBadge): u8 { s.battle_id }
public fun hero_id(s: &FinaleBadge): u8 { s.hero_id }
public fun title(s: &FinaleBadge): &String { &s.title }
public fun inscription(s: &FinaleBadge): &String { &s.inscription }
public fun rating(s: &FinaleBadge): u8 { s.rating }
public fun mint_order(s: &FinaleBadge): u64 { s.mint_order }
public fun is_first_chronicler(s: &FinaleBadge): bool { s.is_first_chronicler }
public fun mint_timestamp_ms(s: &FinaleBadge): u64 { s.mint_timestamp_ms }
public fun player(s: &FinaleBadge): address { s.player }

public fun has_minted(registry: &FinaleRegistry, who: address): bool {
    table::contains(&registry.minted, who)
}
public fun total_minted(registry: &FinaleRegistry): u64 { registry.total_minted }
public fun version(registry: &FinaleRegistry): u64 { registry.version }
public fun is_paused(registry: &FinaleRegistry): bool { registry.paused }

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let registry = FinaleRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        minted: table::new<address, bool>(ctx),
        total_minted: 0,
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    };
    transfer::share_object(registry);
}

#[test_only]
/// Mint bypassing the voucher, to test one-per-player / order logic.
public fun mint_for_testing(
    registry: &mut FinaleRegistry,
    hero_id: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let player = tx_context::sender(ctx);
    assert!(!table::contains(&registry.minted, player), EAlreadyMinted);
    table::add(&mut registry.minted, player, true);
    registry.total_minted = registry.total_minted + 1;
    let next_order = registry.total_minted;
    let badge = FinaleBadge {
        id: object::new(ctx),
        battle_id: FINALE_BATTLE_ID,
        hero_id,
        title: string::utf8(b"t"),
        inscription: string::utf8(b""),
        rating: 0,
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        player,
    };
    transfer::transfer(badge, player);
}
