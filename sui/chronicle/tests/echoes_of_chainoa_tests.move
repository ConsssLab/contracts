#[test_only]
module chronicle::echoes_of_chainoa_tests;

use chronicle::echoes_of_chainoa::{Self as finale, FinaleBadge, FinaleRegistry};
use sui::clock;
use sui::test_scenario as ts;

const PLAYER_A: address = @0xA11CE;
const PLAYER_B: address = @0xB0B;
const FAR_FUTURE_MS: u64 = 9_999_999_999_999;

#[test]
fun mint_finale_happy_path() {
    let mut sc = ts::begin(PLAYER_A);
    finale::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<FinaleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    finale::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let badge = ts::take_from_sender<FinaleBadge>(&sc);
    assert!(finale::battle_id(&badge) == 3, 100);
    assert!(finale::mint_order(&badge) == 1, 101);
    assert!(finale::is_first_chronicler(&badge), 102);
    assert!(finale::player(&badge) == PLAYER_A, 103);
    ts::return_to_sender(&sc, badge);

    assert!(finale::has_minted(&reg, PLAYER_A), 200);
    assert!(!finale::has_minted(&reg, PLAYER_B), 201);
    assert!(finale::total_minted(&reg) == 1, 202);
    assert!(finale::version(&reg) == 1 && !finale::is_paused(&reg), 203);

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = finale::EAlreadyMinted)]
fun rejects_double_mint_by_same_player() {
    let mut sc = ts::begin(PLAYER_A);
    finale::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<FinaleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    finale::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    finale::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
fun two_players_increasing_order() {
    let mut sc = ts::begin(PLAYER_A);
    finale::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<FinaleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    finale::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_B);
    finale::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_B);
    let b = ts::take_from_sender<FinaleBadge>(&sc);
    assert!(finale::mint_order(&b) == 2 && !finale::is_first_chronicler(&b), 300);
    ts::return_to_sender(&sc, b);
    assert!(finale::total_minted(&reg) == 2, 400);

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = finale::EInvalidBattle)]
fun rejects_non_finale_battle() {
    let mut sc = ts::begin(PLAYER_A);
    finale::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<FinaleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    finale::mint_finale(
        &mut reg, 1, 1, b"Title", b"x", 0,
        0, FAR_FUTURE_MS, vector::empty<u8>(), &clk, ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = finale::EAuthorityNotSet)]
fun rejects_mint_when_authority_unset() {
    let mut sc = ts::begin(PLAYER_A);
    finale::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<FinaleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    finale::mint_finale(
        &mut reg, 3, 3, b"Valid", b"ok", 0,
        0, FAR_FUTURE_MS, vector::empty<u8>(), &clk, ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}
