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
// ANTI-CHEAT (voucher) — like chronicle, the mint is NOT open. `mint_witness`
// requires an ed25519 voucher signed by the game's authority key (held
// off-chain). The voucher attests that the player cleared Battle 3. Replay is
// blocked by a one-time `nonce`, staleness by `expiry_ms` vs the on-chain clock.
//
//   Voucher message = domain prefix ++ BCS bytes, in this exact order
//   (backend signer must match byte-for-byte):
//     b"ConSSSWars/witness-voucher/v1" ++ player:address(32) ++ battle_id:u8
//       ++ hero_id:u8 ++ rating:u8 ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
//   The domain prefix is distinct from chronicle's, so a chronicle voucher can
//   never be replayed as a witness voucher (even with the same authority key).
// ============================================================================

module chronicle::witness_seal;

use std::string::{Self, String};
use std::bcs;
use sui::clock::{Self, Clock};
use sui::display;
use sui::ed25519;
use sui::event;
use sui::package;
use sui::table::{Self, Table};
// Reuse chronicle's AdminCap as the single admin capability for the whole
// package — one cap controls both chronicle and witness admin.
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

/// Code-version gate; every player-facing entry asserts the shared registry
/// carries this same version, so `migrate` after an upgrade locks out old code.
const VERSION: u64 = 1;

const WITNESS_BATTLE_ID: u8 = 3;
// Title / inscription are validated in bytes; CJK characters take 3-4 bytes
// in UTF-8, so a 50-character (zh-TW) inscription needs ~200 bytes.
const MAX_TITLE_LEN: u64 = 320;
const MAX_INSCRIPTION_LEN: u64 = 200;
const MAX_HERO_ID: u8 = 20;
const MAX_RATING: u8 = 3;

/// Domain-separation prefix bound into the voucher message (distinct from
/// chronicle's). The off-chain signer MUST prepend these exact bytes.
const VOUCHER_DOMAIN: vector<u8> = b"ConSSSWars/witness-voucher/v1";

// ---------- One-time witness for Display ----------

public struct WITNESS_SEAL has drop {}

// ---------- Types ----------

/// Shared registry: one-per-player tracking, running mint_order, the voucher
/// authority public key, used nonces (replay), and the version/pause gate.
public struct WitnessRegistry has key {
    id: UID,
    /// Code-version gate (see VERSION).
    version: u64,
    /// Operational kill-switch: when true, mint aborts.
    paused: bool,
    /// Players who have minted (one-per-player enforcement).
    minted: Table<address, bool>,
    /// Number of seals minted so far.
    total_minted: u64,
    /// ed25519 public key (32 bytes) of the off-chain voucher signer. Empty
    /// until set via `set_authority_pubkey`; mint aborts while empty.
    authority_pubkey: vector<u8>,
    /// Spent voucher nonces (replay protection).
    used_nonces: Table<u64, bool>,
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
        string::utf8(b"https://conssslab.github.io/public-assets/witness/seal.png"),
        string::utf8(b"https://conssswars.com"),
        string::utf8(b"ConsssLab"),
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

    // Admin uses chronicle::AdminCap (created in chronicle's init) — ONE cap for
    // the whole package controls both chronicle and witness admin.

    let registry = WitnessRegistry {
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

/// Set/rotate the voucher authority ed25519 public key (32 bytes).
public entry fun set_authority_pubkey(
    _admin: &AdminCap,
    registry: &mut WitnessRegistry,
    pubkey: vector<u8>,
) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(vector::length(&pubkey) == 32, EBadPubkey);
    registry.authority_pubkey = pubkey;
}

/// Pause / unpause minting (operational kill-switch). Admin-only.
public entry fun set_paused(_admin: &AdminCap, registry: &mut WitnessRegistry, paused: bool) {
    assert!(registry.version == VERSION, EWrongVersion);
    registry.paused = paused;
}

/// After a package upgrade, bump the registry to the new code VERSION. Admin-only.
public entry fun migrate(_admin: &AdminCap, registry: &mut WitnessRegistry) {
    assert!(registry.version < VERSION, EAlreadyMigrated);
    registry.version = VERSION;
}

/// Version gate + pause switch — every player-facing entry must pass this.
fun assert_active(registry: &WitnessRegistry) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(!registry.paused, EPaused);
}

// ---------- Mint ----------

/// Mint a Validators' Witness seal for the calling player. Requires a valid
/// authority voucher attesting Battle-3 clearance (see module header). The seal
/// is soulbound to the caller.
public entry fun mint_witness(
    registry: &mut WitnessRegistry,
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
    // ---- version gate + pause switch ----
    assert_active(registry);

    // ---- validate fields ----
    assert!(battle_id == WITNESS_BATTLE_ID, EInvalidBattle);
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

// ---------- Internal ----------

/// Canonical voucher message — must byte-match the backend signer.
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

public fun version(registry: &WitnessRegistry): u64 { registry.version }
public fun is_paused(registry: &WitnessRegistry): bool { registry.paused }

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let registry = WitnessRegistry {
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
    registry: &mut WitnessRegistry,
    hero_id: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let player = tx_context::sender(ctx);
    assert!(!table::contains(&registry.minted, player), EAlreadyMinted);
    table::add(&mut registry.minted, player, true);
    registry.total_minted = registry.total_minted + 1;
    let next_order = registry.total_minted;
    let seal = WitnessSeal {
        id: object::new(ctx),
        battle_id: WITNESS_BATTLE_ID,
        hero_id,
        title: string::utf8(b"t"),
        inscription: string::utf8(b""),
        rating: 0,
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        player,
    };
    transfer::transfer(seal, player);
}
