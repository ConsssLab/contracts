#[test_only]
module event_01_gift::event_01_gift_tests;

use event_01_gift::event_01_gift::{Self as gift, MintCounter};
use chronicle::chronicle::{Self, ChronicleRegistry};
use sui::clock;
use sui::test_scenario as ts;

const PLAYER: address = @0xA11CE;
const BOB: address = @0xB0B;

fun mk(reg: &mut ChronicleRegistry, battle: u8, clk: &clock::Clock, sc: &mut ts::Scenario): chronicle::Chronicle {
    chronicle::mint_for_testing(reg, battle, 1, 50, b"blob", clk, ts::ctx(sc))
}

#[test]
fun mint_requires_three_battles_one_per_wallet() {
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc)); // t=0, before deadline

    let c1 = mk(&mut creg, 1, &clk, &mut sc);
    let c2 = mk(&mut creg, 2, &clk, &mut sc);
    let c3 = mk(&mut creg, 3, &clk, &mut sc);

    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc));
    assert!(gift::total_minted(&counter) == 1, 1);
    assert!(gift::has_claimed(&counter, PLAYER), 2);

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}

#[test]
#[expected_failure(abort_code = gift::ENotThreeBattles)]
fun rejects_non_distinct_battles() {
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    let c1 = mk(&mut creg, 1, &clk, &mut sc);
    let c2 = mk(&mut creg, 1, &clk, &mut sc);
    let c3 = mk(&mut creg, 2, &clk, &mut sc);
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc));

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}

#[test]
#[expected_failure(abort_code = gift::ENotOwner)]
fun rejects_chronicle_not_owned_by_caller() {
    // Mirrors the frozen-immutable-Chronicle bypass: BOB earned the Chronicles
    // (player == BOB); PLAYER must NOT be able to claim with them.
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, BOB);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));
    let c1 = mk(&mut creg, 1, &clk, &mut sc); // player == BOB
    let c2 = mk(&mut creg, 2, &clk, &mut sc);
    let c3 = mk(&mut creg, 3, &clk, &mut sc);

    ts::next_tx(&mut sc, PLAYER);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc)); // aborts ENotOwner

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}

#[test]
#[expected_failure(abort_code = gift::EWrongBattles)]
fun rejects_battle_outside_event() {
    // Distinct battles {1,2,4} — passes ENotThreeBattles but battle 4 is not
    // part of event #01, so EWrongBattles must fire.
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    let c1 = mk(&mut creg, 1, &clk, &mut sc);
    let c2 = mk(&mut creg, 2, &clk, &mut sc);
    let c3 = mk(&mut creg, 4, &clk, &mut sc); // battle 4 — outside event #01
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc)); // aborts EWrongBattles

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}

#[test]
#[expected_failure(abort_code = gift::EAlreadyClaimed)]
fun rejects_second_claim() {
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    let c1 = mk(&mut creg, 1, &clk, &mut sc);
    let c2 = mk(&mut creg, 2, &clk, &mut sc);
    let c3 = mk(&mut creg, 3, &clk, &mut sc);
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc));

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}

#[test]
#[expected_failure(abort_code = gift::EEventEnded)]
fun rejects_after_deadline() {
    let mut sc = ts::begin(PLAYER);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    gift::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER);
    let mut creg = ts::take_shared<ChronicleRegistry>(&sc);
    let mut counter = ts::take_shared<MintCounter>(&sc);
    let mut clk = clock::create_for_testing(ts::ctx(&mut sc));
    clock::set_for_testing(&mut clk, gift::end_ms(&counter) + 1); // past deadline

    let c1 = mk(&mut creg, 1, &clk, &mut sc);
    let c2 = mk(&mut creg, 2, &clk, &mut sc);
    let c3 = mk(&mut creg, 3, &clk, &mut sc);
    gift::mint(&mut counter, &c1, &c2, &c3, &clk, ts::ctx(&mut sc)); // aborts EEventEnded

    chronicle::destroy_for_testing(c1); chronicle::destroy_for_testing(c2); chronicle::destroy_for_testing(c3);
    clock::destroy_for_testing(clk);
    ts::return_shared(creg); ts::return_shared(counter); ts::end(sc);
}
