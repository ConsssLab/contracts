// Module: chronicle::chronicle
//
// Transferable Chronicle NFT minted by a player after clearing a battle.
//
// ANTI-CHEAT (voucher) — the mint is NOT open. A player cannot mint by crafting
// a PTB directly: `mint_chronicle` requires an ed25519 *voucher* signed by the
// game's authority key (held server-side, off-chain). The voucher attests the
// player's remaining-HP%, which the client cannot forge. Replay is blocked by a
// one-time `nonce`; stale vouchers by `expiry_ms` vs the on-chain clock.
//
//   Voucher message = BCS bytes, in this exact order (backend must match):
//     player:address(32) ++ battle_id:u8 ++ hero_id:u8 ++ hp_pct:u8
//       ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
//   signed by the authority ed25519 secret key; the public key is stored in
//   ChronicleRegistry.authority_pubkey (set/rotated via AdminCap).
//
// TIER (gold/silver/bronze/normal) — ONE NFT type, four visuals via Display.
// "Floor by mint rank, upgrade by HP" (per-battle rank from the registry):
//     rank 1..100   -> Silver floor    | +1 tier if hp% >= 80  => max Gold
//     rank 101..300 -> Bronze floor    | +1 tier if hp% >= 80  => max Silver
//     rank 301..1000-> Normal floor    | +1 tier if hp% >= 80  => max Bronze
//     rank 1001+    -> NO NFT (mint aborts)
//   tier: 0=Normal, 1=Bronze, 2=Silver, 3=Gold. Display image_url is templated
//   by {battle_id} and {tier}, so each NFT renders its tier's art.
//
// The full chronicle payload (battle log, hero pose, screenshot, long text) is
// on Walrus; `metadata_blob_id` anchors the NFT to its blob. Freely transferable
// (key + store). For the soulbound Battle-3 seal see `chronicle::witness_seal`.

module chronicle::chronicle;

use std::string::{Self, String};
use std::bcs;
use sui::clock::{Self, Clock};
use sui::display;
use sui::ed25519;
use sui::event;
use sui::package;
use sui::table::{Self, Table};

// ---------- Errors ----------

const ETitleTooLong: u64 = 1;
const EInscriptionTooLong: u64 = 2;
const EInvalidBattleId: u64 = 3;
const EInvalidHeroId: u64 = 4;
const ETitleEmpty: u64 = 6;
const EBlobIdEmpty: u64 = 7;
const EBlobIdTooLong: u64 = 8;
const EInvalidHp: u64 = 9;
const EAuthorityNotSet: u64 = 10;
const EVoucherExpired: u64 = 11;
const ENonceUsed: u64 = 12;
const EBadSignature: u64 = 13;
const ENoNFT: u64 = 14;
const EBadPubkey: u64 = 15;
const EWrongVersion: u64 = 16;
const EPaused: u64 = 17;
const EAlreadyMigrated: u64 = 18;

// ---------- Constants ----------

/// On-chain code version. Every entry asserts the shared registry carries this
/// same version, so once `migrate` bumps it after a package upgrade, code from
/// the OLD package version (which still hardcodes the old VERSION) can no longer
/// touch the registry. Bump this on each upgrade that adds a `migrate` step.
const VERSION: u64 = 1;

const MAX_TITLE_LEN: u64 = 320;
const MAX_INSCRIPTION_LEN: u64 = 200;
const MAX_BATTLE_ID: u8 = 3;
const MAX_HERO_ID: u8 = 20;
const MAX_BLOB_ID_LEN: u64 = 128;

// Tier ranking (per-battle mint rank).
const RANK_SILVER_FLOOR: u64 = 100;   // 1..100   -> Silver floor
const RANK_BRONZE_FLOOR: u64 = 300;   // 101..300 -> Bronze floor
const RANK_MAX: u64 = 1000;           // 301..1000-> Normal floor; 1001+ -> no NFT
const HP_UPGRADE_THRESHOLD: u8 = 80;  // hp% >= 80 upgrades one tier

// Tier values.
const TIER_NORMAL: u8 = 0;
const TIER_BRONZE: u8 = 1;
const TIER_SILVER: u8 = 2;

// ---------- One-time witness for Display ----------

public struct CHRONICLE has drop {}

// ---------- Types ----------

/// Admin capability: set/rotate the voucher authority public key.
public struct AdminCap has key, store {
    id: UID,
}

/// Shared registry: per-battle mint order + voucher authority + used nonces.
public struct ChronicleRegistry has key {
    id: UID,
    /// Code-version gate (see VERSION). Entries require this == VERSION.
    version: u64,
    /// Operational kill-switch: when true, mint aborts (admin can pause).
    paused: bool,
    /// battle_id -> count of chronicles minted for that battle so far.
    counts: Table<u8, u64>,
    /// ed25519 public key (32 bytes) of the off-chain voucher signer. Empty
    /// until set via `set_authority_pubkey`; mint aborts while empty.
    authority_pubkey: vector<u8>,
    /// Spent voucher nonces (replay protection).
    used_nonces: Table<u64, bool>,
}

/// Transferable Chronicle NFT.
public struct Chronicle has key, store {
    id: UID,
    battle_id: u8,
    hero_id: u8,
    title: String,
    inscription: String,
    /// Remaining HP% at clear (0..100), attested by the voucher.
    hp_pct: u8,
    /// 0=Normal, 1=Bronze, 2=Silver, 3=Gold. Derived from rank + hp_pct.
    tier: u8,
    mint_order: u64,
    is_first_chronicler: bool,
    mint_timestamp_ms: u64,
    metadata_blob_id: String,
    player: address,
}

// ---------- Events ----------

public struct ChronicleMinted has copy, drop {
    chronicle_id: ID,
    player: address,
    battle_id: u8,
    mint_order: u64,
    tier: u8,
    is_first: bool,
}

// ---------- init ----------

fun init(otw: CHRONICLE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    // image_url is templated by {battle_id} AND {tier} so every battle×tier
    // renders its own artwork from a single NFT type. Host on a CORS-friendly
    // HTTPS path (GitHub Pages here; can move to conssswars.com later).
    let keys = vector[
        string::utf8(b"name"),
        string::utf8(b"description"),
        string::utf8(b"image_url"),
        string::utf8(b"project_url"),
        string::utf8(b"creator"),
        string::utf8(b"tier"),
        string::utf8(b"walrus_blob_id"),
        string::utf8(b"walrus_url"),
    ];
    let values = vector[
        string::utf8(b"{title}"),
        string::utf8(
            b"A Chronicle of the Chainoa Eternal Chronicles. Battle {battle_id}, written by chronicler #{mint_order}.",
        ),
        string::utf8(b"https://conssslab.github.io/public-assets/chronicle/battle-{battle_id}-{tier}.png"),
        string::utf8(b"https://conssswars.com"),
        string::utf8(b"ConsssLab"),
        string::utf8(b"{tier}"),
        string::utf8(b"{metadata_blob_id}"),
        string::utf8(b"https://aggregator.walrus-testnet.walrus.space/v1/blobs/{metadata_blob_id}"),
    ];

    let mut display = display::new_with_fields<Chronicle>(&publisher, keys, values, ctx);
    display::update_version(&mut display);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(display, tx_context::sender(ctx));

    // AdminCap to the deployer.
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));

    // Share the registry (authority key set post-deploy via set_authority_pubkey).
    transfer::share_object(ChronicleRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        counts: table::new<u8, u64>(ctx),
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    });
}

// ---------- Admin ----------

/// Set/rotate the voucher authority ed25519 public key (32 bytes).
public entry fun set_authority_pubkey(
    _admin: &AdminCap,
    registry: &mut ChronicleRegistry,
    pubkey: vector<u8>,
) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(vector::length(&pubkey) == 32, EBadPubkey);
    registry.authority_pubkey = pubkey;
}

/// Pause / unpause minting (operational kill-switch). Admin-only.
public entry fun set_paused(_admin: &AdminCap, registry: &mut ChronicleRegistry, paused: bool) {
    assert!(registry.version == VERSION, EWrongVersion);
    registry.paused = paused;
}

/// After a package upgrade, bump the registry to the new code VERSION. Old
/// package code (which still asserts the old VERSION) can no longer use the
/// registry once this runs. Admin-only; can only move the version forward.
public entry fun migrate(_admin: &AdminCap, registry: &mut ChronicleRegistry) {
    assert!(registry.version < VERSION, EAlreadyMigrated);
    registry.version = VERSION;
}

/// Version gate + pause switch — every player-facing entry must pass this.
fun assert_active(registry: &ChronicleRegistry) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(!registry.paused, EPaused);
}

// ---------- Mint ----------

/// Mint a Chronicle NFT for the calling player. Requires a valid authority
/// voucher (see module header for the signed message layout). The tier is
/// computed on-chain from the per-battle rank + the voucher-attested hp_pct.
public entry fun mint_chronicle(
    registry: &mut ChronicleRegistry,
    battle_id: u8,
    hero_id: u8,
    title: vector<u8>,
    inscription: vector<u8>,
    hp_pct: u8,
    metadata_blob_id: vector<u8>,
    nonce: u64,
    expiry_ms: u64,
    signature: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // ---- version gate + pause switch ----
    assert_active(registry);

    // ---- validate fields ----
    assert!(battle_id >= 1 && battle_id <= MAX_BATTLE_ID, EInvalidBattleId);
    assert!(hero_id >= 1 && hero_id <= MAX_HERO_ID, EInvalidHeroId);
    assert!(hp_pct <= 100, EInvalidHp);

    let title_len = vector::length(&title);
    assert!(title_len > 0, ETitleEmpty);
    assert!(title_len <= MAX_TITLE_LEN, ETitleTooLong);
    assert!(vector::length(&inscription) <= MAX_INSCRIPTION_LEN, EInscriptionTooLong);

    let blob_id_len = vector::length(&metadata_blob_id);
    assert!(blob_id_len > 0, EBlobIdEmpty);
    assert!(blob_id_len <= MAX_BLOB_ID_LEN, EBlobIdTooLong);

    let player = tx_context::sender(ctx);

    // ---- verify voucher (anti-cheat) ----
    assert!(vector::length(&registry.authority_pubkey) == 32, EAuthorityNotSet);
    assert!(clock::timestamp_ms(clock) <= expiry_ms, EVoucherExpired);
    assert!(!table::contains(&registry.used_nonces, nonce), ENonceUsed);
    let msg = build_voucher_message(player, battle_id, hero_id, hp_pct, nonce, expiry_ms);
    assert!(ed25519::ed25519_verify(&signature, &registry.authority_pubkey, &msg), EBadSignature);
    table::add(&mut registry.used_nonces, nonce, true);

    // ---- per-battle rank gate: #1001+ get no NFT ----
    let current = current_count(registry, battle_id);
    assert!(current < RANK_MAX, ENoNFT);
    let next_order = current + 1;
    set_count(registry, battle_id, next_order);

    let tier = compute_tier(next_order, hp_pct);

    let nft = Chronicle {
        id: object::new(ctx),
        battle_id,
        hero_id,
        title: string::utf8(title),
        inscription: string::utf8(inscription),
        hp_pct,
        tier,
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        metadata_blob_id: string::utf8(metadata_blob_id),
        player,
    };

    event::emit(ChronicleMinted {
        chronicle_id: object::id(&nft),
        player,
        battle_id,
        mint_order: next_order,
        tier,
        is_first: next_order == 1,
    });

    transfer::public_transfer(nft, player);
}

// ---------- Internal ----------

/// Floor-by-rank, upgrade-by-HP. Caller must ensure rank <= RANK_MAX.
fun compute_tier(rank: u64, hp_pct: u8): u8 {
    let floor = if (rank <= RANK_SILVER_FLOOR) {
        TIER_SILVER
    } else if (rank <= RANK_BRONZE_FLOOR) {
        TIER_BRONZE
    } else {
        TIER_NORMAL
    };
    if (hp_pct >= HP_UPGRADE_THRESHOLD) { floor + 1 } else { floor }
}

/// Canonical voucher message — must byte-match the backend signer.
fun build_voucher_message(
    player: address,
    battle_id: u8,
    hero_id: u8,
    hp_pct: u8,
    nonce: u64,
    expiry_ms: u64,
): vector<u8> {
    let mut m = bcs::to_bytes(&player);
    vector::append(&mut m, bcs::to_bytes(&battle_id));
    vector::append(&mut m, bcs::to_bytes(&hero_id));
    vector::append(&mut m, bcs::to_bytes(&hp_pct));
    vector::append(&mut m, bcs::to_bytes(&nonce));
    vector::append(&mut m, bcs::to_bytes(&expiry_ms));
    m
}

fun current_count(registry: &ChronicleRegistry, battle_id: u8): u64 {
    if (table::contains(&registry.counts, battle_id)) {
        *table::borrow(&registry.counts, battle_id)
    } else {
        0
    }
}

fun set_count(registry: &mut ChronicleRegistry, battle_id: u8, value: u64) {
    if (table::contains(&registry.counts, battle_id)) {
        *table::borrow_mut(&mut registry.counts, battle_id) = value;
    } else {
        table::add(&mut registry.counts, battle_id, value);
    }
}

// ---------- Read accessors ----------

public fun battle_id(c: &Chronicle): u8 { c.battle_id }
public fun hero_id(c: &Chronicle): u8 { c.hero_id }
public fun title(c: &Chronicle): &String { &c.title }
public fun inscription(c: &Chronicle): &String { &c.inscription }
public fun hp_pct(c: &Chronicle): u8 { c.hp_pct }
public fun tier(c: &Chronicle): u8 { c.tier }
public fun mint_order(c: &Chronicle): u64 { c.mint_order }
public fun is_first_chronicler(c: &Chronicle): bool { c.is_first_chronicler }
public fun mint_timestamp_ms(c: &Chronicle): u64 { c.mint_timestamp_ms }
public fun metadata_blob_id(c: &Chronicle): &String { &c.metadata_blob_id }
public fun player(c: &Chronicle): address { c.player }

public fun count_for_battle(registry: &ChronicleRegistry, battle_id: u8): u64 {
    current_count(registry, battle_id)
}

public fun version(registry: &ChronicleRegistry): u64 { registry.version }
public fun is_paused(registry: &ChronicleRegistry): bool { registry.paused }

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    transfer::share_object(ChronicleRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        counts: table::new<u8, u64>(ctx),
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    });
}

#[test_only]
/// Mint bypassing the voucher, to test rank/tier logic. Returns the NFT.
public fun mint_for_testing(
    registry: &mut ChronicleRegistry,
    battle_id: u8,
    hero_id: u8,
    hp_pct: u8,
    metadata_blob_id: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
): Chronicle {
    let current = current_count(registry, battle_id);
    assert!(current < RANK_MAX, ENoNFT);
    let next_order = current + 1;
    set_count(registry, battle_id, next_order);
    Chronicle {
        id: object::new(ctx),
        battle_id,
        hero_id,
        title: string::utf8(b"t"),
        inscription: string::utf8(b""),
        hp_pct,
        tier: compute_tier(next_order, hp_pct),
        mint_order: next_order,
        is_first_chronicler: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        metadata_blob_id: string::utf8(metadata_blob_id),
        player: tx_context::sender(ctx),
    }
}

#[test_only]
public fun set_count_for_testing(registry: &mut ChronicleRegistry, battle_id: u8, value: u64) {
    set_count(registry, battle_id, value);
}

#[test_only]
public fun destroy_for_testing(c: Chronicle) {
    let Chronicle { id, battle_id: _, hero_id: _, title: _, inscription: _, hp_pct: _, tier: _, mint_order: _, is_first_chronicler: _, mint_timestamp_ms: _, metadata_blob_id: _, player: _ } = c;
    object::delete(id);
}
