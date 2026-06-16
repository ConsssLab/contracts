// Module: sovereign_minds::sovereign
//
// Transferable Deed NFT minted after clearing a Sovereign Minds (群雄覺醒)
// water-chapter battle. Same family as chronicle::chronicle, but ONE thing
// changes and it is the whole point of this installment:
//
//   Echoes' voucher attested `hp_pct` — a number the CLIENT reports. The
//   server signed whatever the client claimed (the documented "client-side
//   game ceiling"). Sovereign Minds attests `score_milli` (the clearance
//   score z, ×1000) COMPUTED BY THE SERVER from a server-authoritative match
//   (see play/functions/api/match/* + play/shared/*). The client never reports
//   an outcome; it sends actions, the server simulates, the server scores, the
//   server signs. So a voucher here means "this match was actually played and
//   actually won under the real rules" — not "the client said so".
//
// The on-chain anti-cheat plumbing is unchanged from chronicle and equally
// strict: mint requires an ed25519 voucher signed by the authority key (held
// server-side); replay blocked by a one-time `nonce`; staleness by `expiry_ms`
// vs the on-chain clock; the voucher is bound to THIS registry (no cross-
// deployment replay) and to a distinct domain prefix (no cross-game replay).
//
//   Voucher message = domain prefix ++ BCS bytes, in this EXACT order
//   (the off-chain signer in play/shared/voucher.js must byte-match):
//     b"ConSSSWars/sovereign-voucher/v1" ++ registry_id:address(32)
//       ++ player:address(32) ++ battle_id:u8 ++ hero_id:u8 ++ hp_pct:u8
//       ++ score_milli:u64(LE,8) ++ nonce:u64(LE,8) ++ expiry_ms:u64(LE,8)
//
// TIER (gold/silver/bronze/normal) — ONE NFT type, four visuals via Display.
// "Floor by mint rank, upgrade by performance":
//     rank 1..100    -> Silver floor   | +1 tier if upgraded => max Gold
//     rank 101..300  -> Bronze floor   | +1 tier if upgraded => max Silver
//     rank 301..1000 -> Normal floor   | +1 tier if upgraded => max Bronze
//     rank 1001+     -> NO NFT (mint aborts)
//   "upgraded" = hp_pct >= 80 OR score_milli >= registry.score_upgrade_threshold.
//   The score path is what makes z matter on-chain; the threshold is admin-
//   tunable (defaults very high = effectively HP-only until tuned per battle).
//   tier: 0=Normal, 1=Bronze, 2=Silver, 3=Gold.
//
// The full match payload (deterministic input-log for replay verification, the
// commander's decisions, hero pose, screenshot) lives on Walrus;
// `metadata_blob_id` anchors the NFT to its blob. Storing the replayable log is
// also the cheap first step toward trustlessness (anyone can re-run the
// deterministic parts) on the road to a TEE (Nautilus) attestation later.

module sovereign_minds::sovereign;

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
const EBadSigLen: u64 = 19;

// ---------- Constants ----------

/// On-chain code version. Every entry asserts the shared registry carries this
/// same version, so once `migrate` bumps it after a package upgrade, code from
/// the OLD package version can no longer touch the registry. Bump on each
/// upgrade that adds a `migrate` step. (Echoes' early modules shipped WITHOUT
/// this gate — see the audit note in MEMORY; this package has it from v1, which
/// is one reason it is a fresh package rather than a chronicle upgrade.)
const VERSION: u64 = 1;

const MAX_TITLE_LEN: u64 = 320;
const MAX_INSCRIPTION_LEN: u64 = 200;
// Defaults for the admin-configurable per-registry caps. The water chapter is
// 3 fixed battles; heroes expand over installments. Raised via setters, no code
// change needed.
const DEFAULT_MAX_BATTLE_ID: u8 = 3;
const DEFAULT_MAX_HERO_ID: u8 = 20;
const MAX_BLOB_ID_LEN: u64 = 128;

/// Default score upgrade threshold (milli-z). Set absurdly high so that until
/// an admin tunes per-battle thresholds, tier upgrade is driven by hp only
/// (identical to chronicle's proven behavior). Lowering it later lets a high z
/// alone earn the tier bump — no code change, no new trust surface.
const DEFAULT_SCORE_UPGRADE_THRESHOLD: u64 = 18_446_744_073_709_551_615; // u64::MAX

/// Domain-separation prefix bound into the voucher message. Distinct from
/// chronicle's and echoes' domains so no signature can be cross-replayed
/// between games. The off-chain signer MUST prepend these exact bytes.
const VOUCHER_DOMAIN: vector<u8> = b"ConSSSWars/sovereign-voucher/v1";

// Tier ranking (per-battle mint rank).
const RANK_SILVER_FLOOR: u64 = 100;   // 1..100    -> Silver floor
const RANK_BRONZE_FLOOR: u64 = 300;   // 101..300  -> Bronze floor
const RANK_MAX: u64 = 1000;           // 301..1000 -> Normal floor; 1001+ -> no NFT
const HP_UPGRADE_THRESHOLD: u8 = 80;  // hp% >= 80 upgrades one tier

// Tier values.
const TIER_NORMAL: u8 = 0;
const TIER_BRONZE: u8 = 1;
const TIER_SILVER: u8 = 2;

// ---------- One-time witness for Display ----------

public struct SOVEREIGN has drop {}

// ---------- Types ----------

/// Admin capability: rotate the voucher authority key, pause, migrate, tune.
public struct AdminCap has key, store {
    id: UID,
}

/// Shared registry: per-battle mint order + voucher authority + used nonces +
/// tunables.
public struct SovereignRegistry has key {
    id: UID,
    /// Code-version gate (see VERSION). Entries require this == VERSION.
    version: u64,
    /// Operational kill-switch: when true, mint aborts (admin can pause).
    paused: bool,
    /// Admin-configurable accepted ranges (defaults 3 / 20).
    max_battle_id: u8,
    max_hero_id: u8,
    /// Score (milli-z) at/above which tier upgrades by one, independent of hp.
    score_upgrade_threshold: u64,
    /// battle_id -> count of deeds minted for that battle so far.
    counts: Table<u8, u64>,
    /// ed25519 public key (32 bytes) of the off-chain voucher signer. Empty
    /// until set via `set_authority_pubkey`; mint aborts while empty.
    authority_pubkey: vector<u8>,
    /// Spent voucher nonces (replay protection).
    used_nonces: Table<u64, bool>,
}

/// Transferable Sovereign Deed NFT.
public struct SovereignDeed has key, store {
    id: UID,
    battle_id: u8,
    hero_id: u8,
    /// Remaining HP% at clear (0..100), attested by the voucher.
    hp_pct: u8,
    /// Clearance score z ×1000 (server-computed, voucher-attested). The
    /// headline stat and the leaderboard key. Floors at 0 (server clamps).
    score_milli: u64,
    /// 0=Normal, 1=Bronze, 2=Silver, 3=Gold. Derived from rank + hp + score.
    tier: u8,
    title: String,
    inscription: String,
    mint_order: u64,
    is_first_sovereign: bool,
    mint_timestamp_ms: u64,
    metadata_blob_id: String,
    player: address,
}

// ---------- Events ----------

public struct DeedMinted has copy, drop {
    deed_id: ID,
    player: address,
    battle_id: u8,
    hero_id: u8,
    score_milli: u64,
    mint_order: u64,
    tier: u8,
    is_first: bool,
}

// ---------- init ----------

fun init(otw: SOVEREIGN, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    // image_url templated by {battle_id} AND {tier} so every battle×tier renders
    // its own artwork from a single NFT type. Hosted on the (renamed) org's
    // GitHub Pages — same CORS-friendly pattern chronicle uses.
    let keys = vector[
        string::utf8(b"name"),
        string::utf8(b"description"),
        string::utf8(b"image_url"),
        string::utf8(b"project_url"),
        string::utf8(b"creator"),
        string::utf8(b"tier"),
        string::utf8(b"score_milli"),
        string::utf8(b"walrus_blob_id"),
        string::utf8(b"walrus_url"),
    ];
    let values = vector[
        string::utf8(b"{title}"),
        string::utf8(
            b"A Sovereign Deed of ConSSS Wars: Sovereign Minds. Battle {battle_id}, score {score_milli} (milli-z), sealed by sovereign #{mint_order}.",
        ),
        string::utf8(b"https://conssslab.github.io/public-assets/sovereign/battle-{battle_id}-{tier}.png"),
        string::utf8(b"https://conssswars.com"),
        string::utf8(b"ConsssLab"),
        string::utf8(b"{tier}"),
        string::utf8(b"{score_milli}"),
        string::utf8(b"{metadata_blob_id}"),
        string::utf8(b"https://aggregator.walrus-mainnet.walrus.space/v1/blobs/{metadata_blob_id}"),
    ];

    let mut display = display::new_with_fields<SovereignDeed>(&publisher, keys, values, ctx);
    display::update_version(&mut display);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(display, tx_context::sender(ctx));
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));

    transfer::share_object(SovereignRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        max_battle_id: DEFAULT_MAX_BATTLE_ID,
        max_hero_id: DEFAULT_MAX_HERO_ID,
        score_upgrade_threshold: DEFAULT_SCORE_UPGRADE_THRESHOLD,
        counts: table::new<u8, u64>(ctx),
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    });
}

// ---------- Admin ----------

/// Set/rotate the voucher authority ed25519 public key (32 bytes).
public entry fun set_authority_pubkey(
    _admin: &AdminCap,
    registry: &mut SovereignRegistry,
    pubkey: vector<u8>,
) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(vector::length(&pubkey) == 32, EBadPubkey);
    registry.authority_pubkey = pubkey;
}

/// Pause / unpause minting (operational kill-switch). Admin-only.
public entry fun set_paused(_admin: &AdminCap, registry: &mut SovereignRegistry, paused: bool) {
    assert!(registry.version == VERSION, EWrongVersion);
    registry.paused = paused;
}

/// After a package upgrade, bump the registry to the new code VERSION.
public entry fun migrate(_admin: &AdminCap, registry: &mut SovereignRegistry) {
    assert!(registry.version < VERSION, EAlreadyMigrated);
    registry.version = VERSION;
}

/// Raise/adjust the max battle id accepted by mint. Admin-only, >= 1.
public entry fun set_max_battle_id(_admin: &AdminCap, registry: &mut SovereignRegistry, value: u8) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(value >= 1, EInvalidBattleId);
    registry.max_battle_id = value;
}

/// Raise/adjust the max hero id accepted by mint. Admin-only, >= 1.
public entry fun set_max_hero_id(_admin: &AdminCap, registry: &mut SovereignRegistry, value: u8) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(value >= 1, EInvalidHeroId);
    registry.max_hero_id = value;
}

/// Tune the milli-z at/above which tier upgrades by one (independent of hp).
/// Admin-only. Lowering it makes a high score alone worth a tier bump; it never
/// loosens the voucher requirement, so no new trust surface.
public entry fun set_score_upgrade_threshold(
    _admin: &AdminCap,
    registry: &mut SovereignRegistry,
    value: u64,
) {
    assert!(registry.version == VERSION, EWrongVersion);
    registry.score_upgrade_threshold = value;
}

/// Version gate + pause switch — every player-facing entry must pass this.
fun assert_active(registry: &SovereignRegistry) {
    assert!(registry.version == VERSION, EWrongVersion);
    assert!(!registry.paused, EPaused);
}

// ---------- Mint ----------

/// Mint a Sovereign Deed for the calling player. Requires a valid authority
/// voucher (see module header for the signed message layout). The tier is
/// computed on-chain from the per-battle rank + the voucher-attested hp_pct and
/// score_milli.
public entry fun mint_deed(
    registry: &mut SovereignRegistry,
    battle_id: u8,
    hero_id: u8,
    title: vector<u8>,
    inscription: vector<u8>,
    hp_pct: u8,
    score_milli: u64,
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
    assert!(battle_id >= 1 && battle_id <= registry.max_battle_id, EInvalidBattleId);
    assert!(hero_id >= 1 && hero_id <= registry.max_hero_id, EInvalidHeroId);
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
    assert!(vector::length(&signature) == 64, EBadSigLen);
    let msg = build_voucher_message(
        object::id_address(registry), player, battle_id, hero_id, hp_pct, score_milli, nonce, expiry_ms,
    );
    assert!(ed25519::ed25519_verify(&signature, &registry.authority_pubkey, &msg), EBadSignature);
    table::add(&mut registry.used_nonces, nonce, true);

    // ---- per-battle rank gate: #1001+ get no NFT ----
    let current = current_count(registry, battle_id);
    assert!(current < RANK_MAX, ENoNFT);
    let next_order = current + 1;
    set_count(registry, battle_id, next_order);

    let tier = compute_tier(next_order, hp_pct, score_milli, registry.score_upgrade_threshold);

    let nft = SovereignDeed {
        id: object::new(ctx),
        battle_id,
        hero_id,
        hp_pct,
        score_milli,
        tier,
        title: string::utf8(title),
        inscription: string::utf8(inscription),
        mint_order: next_order,
        is_first_sovereign: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        metadata_blob_id: string::utf8(metadata_blob_id),
        player,
    };

    event::emit(DeedMinted {
        deed_id: object::id(&nft),
        player,
        battle_id,
        hero_id,
        score_milli,
        mint_order: next_order,
        tier,
        is_first: next_order == 1,
    });

    transfer::public_transfer(nft, player);
}

// ---------- Internal ----------

/// Floor-by-rank, upgrade-by-performance (hp OR score). Caller ensures
/// rank <= RANK_MAX. A single upgrade step, capped at Gold (Silver floor + 1).
fun compute_tier(rank: u64, hp_pct: u8, score_milli: u64, score_threshold: u64): u8 {
    let floor = if (rank <= RANK_SILVER_FLOOR) {
        TIER_SILVER
    } else if (rank <= RANK_BRONZE_FLOOR) {
        TIER_BRONZE
    } else {
        TIER_NORMAL
    };
    let upgraded = hp_pct >= HP_UPGRADE_THRESHOLD || score_milli >= score_threshold;
    if (upgraded) { floor + 1 } else { floor }
}

/// Canonical voucher message — must byte-match the backend signer
/// (play/shared/voucher.js). Layout:
///   DOMAIN ++ registry_id:address(32) ++ player:address(32)
///     ++ battle_id:u8 ++ hero_id:u8 ++ hp_pct:u8
///     ++ score_milli:u64(LE) ++ nonce:u64(LE) ++ expiry_ms:u64(LE)
fun build_voucher_message(
    registry_id: address,
    player: address,
    battle_id: u8,
    hero_id: u8,
    hp_pct: u8,
    score_milli: u64,
    nonce: u64,
    expiry_ms: u64,
): vector<u8> {
    let mut m = VOUCHER_DOMAIN;
    vector::append(&mut m, bcs::to_bytes(&registry_id));
    vector::append(&mut m, bcs::to_bytes(&player));
    vector::append(&mut m, bcs::to_bytes(&battle_id));
    vector::append(&mut m, bcs::to_bytes(&hero_id));
    vector::append(&mut m, bcs::to_bytes(&hp_pct));
    vector::append(&mut m, bcs::to_bytes(&score_milli));
    vector::append(&mut m, bcs::to_bytes(&nonce));
    vector::append(&mut m, bcs::to_bytes(&expiry_ms));
    m
}

#[test_only]
public fun build_voucher_message_for_testing(
    registry_id: address, player: address, battle_id: u8, hero_id: u8, hp_pct: u8,
    score_milli: u64, nonce: u64, expiry_ms: u64,
): vector<u8> {
    build_voucher_message(registry_id, player, battle_id, hero_id, hp_pct, score_milli, nonce, expiry_ms)
}

fun current_count(registry: &SovereignRegistry, battle_id: u8): u64 {
    if (table::contains(&registry.counts, battle_id)) {
        *table::borrow(&registry.counts, battle_id)
    } else {
        0
    }
}

fun set_count(registry: &mut SovereignRegistry, battle_id: u8, value: u64) {
    if (table::contains(&registry.counts, battle_id)) {
        *table::borrow_mut(&mut registry.counts, battle_id) = value;
    } else {
        table::add(&mut registry.counts, battle_id, value);
    }
}

// ---------- Read accessors ----------

public fun battle_id(d: &SovereignDeed): u8 { d.battle_id }
public fun hero_id(d: &SovereignDeed): u8 { d.hero_id }
public fun hp_pct(d: &SovereignDeed): u8 { d.hp_pct }
public fun score_milli(d: &SovereignDeed): u64 { d.score_milli }
public fun tier(d: &SovereignDeed): u8 { d.tier }
public fun title(d: &SovereignDeed): &String { &d.title }
public fun inscription(d: &SovereignDeed): &String { &d.inscription }
public fun mint_order(d: &SovereignDeed): u64 { d.mint_order }
public fun is_first_sovereign(d: &SovereignDeed): bool { d.is_first_sovereign }
public fun mint_timestamp_ms(d: &SovereignDeed): u64 { d.mint_timestamp_ms }
public fun metadata_blob_id(d: &SovereignDeed): &String { &d.metadata_blob_id }
public fun player(d: &SovereignDeed): address { d.player }

public fun count_for_battle(registry: &SovereignRegistry, battle_id: u8): u64 {
    current_count(registry, battle_id)
}
public fun version(registry: &SovereignRegistry): u64 { registry.version }
public fun is_paused(registry: &SovereignRegistry): bool { registry.paused }
public fun score_upgrade_threshold(registry: &SovereignRegistry): u64 { registry.score_upgrade_threshold }

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    transfer::share_object(SovereignRegistry {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        max_battle_id: DEFAULT_MAX_BATTLE_ID,
        max_hero_id: DEFAULT_MAX_HERO_ID,
        score_upgrade_threshold: DEFAULT_SCORE_UPGRADE_THRESHOLD,
        counts: table::new<u8, u64>(ctx),
        authority_pubkey: vector::empty<u8>(),
        used_nonces: table::new<u64, bool>(ctx),
    });
}

#[test_only]
/// Mint bypassing the voucher, to test rank/tier logic. Returns the NFT.
public fun mint_for_testing(
    registry: &mut SovereignRegistry,
    battle_id: u8,
    hero_id: u8,
    hp_pct: u8,
    score_milli: u64,
    metadata_blob_id: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
): SovereignDeed {
    let current = current_count(registry, battle_id);
    assert!(current < RANK_MAX, ENoNFT);
    let next_order = current + 1;
    set_count(registry, battle_id, next_order);
    SovereignDeed {
        id: object::new(ctx),
        battle_id,
        hero_id,
        hp_pct,
        score_milli,
        tier: compute_tier(next_order, hp_pct, score_milli, registry.score_upgrade_threshold),
        title: string::utf8(b"t"),
        inscription: string::utf8(b""),
        mint_order: next_order,
        is_first_sovereign: next_order == 1,
        mint_timestamp_ms: clock::timestamp_ms(clock),
        metadata_blob_id: string::utf8(metadata_blob_id),
        player: tx_context::sender(ctx),
    }
}

#[test_only]
public fun set_count_for_testing(registry: &mut SovereignRegistry, battle_id: u8, value: u64) {
    set_count(registry, battle_id, value);
}

#[test_only]
public fun set_authority_pubkey_for_testing(registry: &mut SovereignRegistry, pubkey: vector<u8>) {
    registry.authority_pubkey = pubkey;
}

#[test_only]
public fun mint_deed_entry_for_testing(
    registry: &mut SovereignRegistry,
    battle_id: u8, hero_id: u8, title: vector<u8>, inscription: vector<u8>,
    hp_pct: u8, score_milli: u64, metadata_blob_id: vector<u8>,
    nonce: u64, expiry_ms: u64, signature: vector<u8>, clock: &Clock, ctx: &mut TxContext,
) {
    mint_deed(registry, battle_id, hero_id, title, inscription, hp_pct, score_milli, metadata_blob_id, nonce, expiry_ms, signature, clock, ctx);
}

#[test_only]
public fun destroy_for_testing(d: SovereignDeed) {
    let SovereignDeed { id, battle_id: _, hero_id: _, hp_pct: _, score_milli: _, tier: _, title: _, inscription: _, mint_order: _, is_first_sovereign: _, mint_timestamp_ms: _, metadata_blob_id: _, player: _ } = d;
    object::delete(id);
}
