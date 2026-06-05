/// ConSSS Wars — Echoes of Chainoa
/// Limited-time event #01: the "1st Gift" treasure-chest NFT.
///
/// ELIGIBILITY: a wallet may mint exactly ONE gift, only while the event is open
/// (on-chain deadline), and only if it HOLDS Chronicles from three DIFFERENT
/// battles (cleared battles 1, 2 and 3). Holding is proven by passing three
/// `&Chronicle` of the caller's own; the `Chronicle` type guarantees they came
/// from the real (voucher-gated) chronicle package.
///
/// Naming: "event_01" = limited-time event #1; future events get their own
/// numbered module (event_02_…), so this never collides with an in-game gift.
module event_01_gift::event_01_gift;

use std::string::{Self, String};
use sui::clock::{Self, Clock};
use sui::display;
use sui::event;
use sui::package;
use sui::table::{Self, Table};
use chronicle::chronicle::{Self, Chronicle};

// ---------- Errors ----------

const EAlreadyClaimed: u64 = 1;
const ENotThreeBattles: u64 = 2;
const EWrongVersion: u64 = 3;
const EPaused: u64 = 4;
const EAlreadyMigrated: u64 = 5;
const EEventEnded: u64 = 6;
const ENotOwner: u64 = 7;
const EWrongBattles: u64 = 8;

// ---------- Constants ----------

const VERSION: u64 = 1;

/// Event close time (ms since epoch). 2026-06-30 23:59:59 UTC.
/// Admin-adjustable post-deploy via set_end_ms (verify/extend before launch).
const EVENT_END_MS: u64 = 1782863999000;

const NAME: vector<u8> = b"ConSSS Wars - 1st Gift";
const DESCRIPTION: vector<u8> =
    b"Official limited-time event reward of ConSSS Wars: Echoes of Chainoa. A treasure chest opened by the heroes of Chainoa.";
const IMAGE_URL: vector<u8> =
    b"https://raw.githubusercontent.com/ConsssLab/public-assets/main/consss-first-gift/consss-1st-gift.png";
const PROJECT_URL: vector<u8> = b"https://conssswars.com/";

// ---------- Types ----------

public struct Gift has key, store {
    id: UID,
    name: String,
    description: String,
    image_url: String,
    edition: u64,
}

/// Admin capability: pause, set deadline, migrate, and burn (discard governance
/// once the event is over).
public struct GiftAdminCap has key, store {
    id: UID,
}

/// Shared object: edition counter + one-per-wallet tracking + deadline + gate.
public struct MintCounter has key {
    id: UID,
    version: u64,
    paused: bool,
    minted: u64,
    /// Wallets that have already claimed (one gift per wallet).
    claimed: Table<address, bool>,
    /// Event close time (ms). mint aborts once the clock passes this.
    end_ms: u64,
}

public struct EVENT_01_GIFT has drop {}

public struct GiftMinted has copy, drop {
    edition: u64,
    recipient: address,
}

// ---------- init ----------

fun init(otw: EVENT_01_GIFT, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut disp = display::new<Gift>(&publisher, ctx);
    disp.add(string::utf8(b"name"), string::utf8(b"{name} #{edition}"));
    disp.add(string::utf8(b"description"), string::utf8(b"{description}"));
    disp.add(string::utf8(b"image_url"), string::utf8(b"{image_url}"));
    disp.add(string::utf8(b"project_url"), string::utf8(PROJECT_URL));
    disp.add(string::utf8(b"creator"), string::utf8(b"ConsssLab"));
    disp.update_version();

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(disp, ctx.sender());
    transfer::public_transfer(GiftAdminCap { id: object::new(ctx) }, ctx.sender());

    transfer::share_object(MintCounter {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        minted: 0,
        claimed: table::new<address, bool>(ctx),
        end_ms: EVENT_END_MS,
    });
}

// ---------- Admin ----------

public entry fun set_paused(_admin: &GiftAdminCap, counter: &mut MintCounter, paused: bool) {
    assert!(counter.version == VERSION, EWrongVersion);
    counter.paused = paused;
}

/// Adjust the event close time (e.g. to extend). Admin-only.
public entry fun set_end_ms(_admin: &GiftAdminCap, counter: &mut MintCounter, end_ms: u64) {
    assert!(counter.version == VERSION, EWrongVersion);
    counter.end_ms = end_ms;
}

public entry fun migrate(_admin: &GiftAdminCap, counter: &mut MintCounter) {
    assert!(counter.version < VERSION, EAlreadyMigrated);
    counter.version = VERSION;
}

/// Discard governance once the event is over: permanently destroy the admin cap.
/// After this, the event can no longer be paused/extended/migrated — fine for a
/// finished one-shot event.
public entry fun burn_admin_cap(cap: GiftAdminCap) {
    let GiftAdminCap { id } = cap;
    object::delete(id);
}

fun assert_active(counter: &MintCounter, clock: &Clock) {
    assert!(counter.version == VERSION, EWrongVersion);
    assert!(!counter.paused, EPaused);
    assert!(clock::timestamp_ms(clock) <= counter.end_ms, EEventEnded);
}

// ---------- Mint ----------

/// Open a treasure chest: mint a 1st Gift NFT to the caller. Requires the caller
/// to own three Chronicles covering three distinct battles, the event to be open
/// (before deadline), and the caller not to have claimed before.
public fun mint(
    counter: &mut MintCounter,
    c1: &Chronicle,
    c2: &Chronicle,
    c3: &Chronicle,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_active(counter, clock);

    let who = ctx.sender();
    assert!(!table::contains(&counter.claimed, who), EAlreadyClaimed);

    // Each Chronicle must have been EARNED BY the caller. `player` is bound at
    // mint to the voucher recipient, so requiring it to equal the caller rejects:
    //   - frozen/immutable Chronicles: anyone can `public_freeze_object` a
    //     Chronicle and then pass it by `&ref`, but its `player` field is the
    //     original clearer, not the caller; and
    //   - Chronicles transferred to a second wallet to claim in rotation.
    // (This also makes per-Chronicle-ID tracking unnecessary: a given set can
    //  only ever yield its single owner's one claim.)
    assert!(
        chronicle::player(c1) == who
            && chronicle::player(c2) == who
            && chronicle::player(c3) == who,
        ENotOwner,
    );

    let b1 = chronicle::battle_id(c1);
    let b2 = chronicle::battle_id(c2);
    let b3 = chronicle::battle_id(c3);
    // Event #01 is specifically battles 1-3. Distinct + each in {1,2,3} pins the
    // set to exactly {1,2,3}, so a future battle 4+ can't substitute (e.g. 1/4/5).
    assert!(b1 != b2 && b1 != b3 && b2 != b3, ENotThreeBattles);
    assert!(
        b1 >= 1 && b1 <= 3 && b2 >= 1 && b2 <= 3 && b3 >= 1 && b3 <= 3,
        EWrongBattles,
    );

    table::add(&mut counter.claimed, who, true);
    counter.minted = counter.minted + 1;
    let edition = counter.minted;

    let gift = Gift {
        id: object::new(ctx),
        name: string::utf8(NAME),
        description: string::utf8(DESCRIPTION),
        image_url: string::utf8(IMAGE_URL),
        edition,
    };

    event::emit(GiftMinted { edition, recipient: who });
    transfer::public_transfer(gift, who);
}

// ---------- Read accessors ----------

public fun total_minted(counter: &MintCounter): u64 { counter.minted }
public fun has_claimed(counter: &MintCounter, who: address): bool {
    table::contains(&counter.claimed, who)
}
public fun version(counter: &MintCounter): u64 { counter.version }
public fun is_paused(counter: &MintCounter): bool { counter.paused }
public fun end_ms(counter: &MintCounter): u64 { counter.end_ms }

// ---------- Test-only helpers ----------

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    transfer::public_transfer(GiftAdminCap { id: object::new(ctx) }, ctx.sender());
    transfer::share_object(MintCounter {
        id: object::new(ctx),
        version: VERSION,
        paused: false,
        minted: 0,
        claimed: table::new<address, bool>(ctx),
        end_ms: EVENT_END_MS,
    });
}
