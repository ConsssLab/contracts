#[test_only]
module chronicle::witness_seal_tests;

use chronicle::witness_seal::{Self, WitnessSeal, WitnessRegistry};
use sui::clock;
use sui::test_scenario as ts;

const PLAYER_A: address = @0xA11CE;
const PLAYER_B: address = @0xB0B;

#[test]
fun mint_witness_happy_path() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        b"When the Validators Spoke as One",
        b"Decentralization is loud, messy, and beautiful.",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_A);
    let seal = ts::take_from_sender<WitnessSeal>(&sc);
    assert!(witness_seal::battle_id(&seal) == 3, 100);
    assert!(witness_seal::mint_order(&seal) == 1, 101);
    assert!(witness_seal::is_first_chronicler(&seal), 102);
    assert!(witness_seal::player(&seal) == PLAYER_A, 103);
    ts::return_to_sender(&sc, seal);

    assert!(witness_seal::has_minted(&reg, PLAYER_A), 200);
    assert!(!witness_seal::has_minted(&reg, PLAYER_B), 201);
    assert!(witness_seal::total_minted(&reg) == 1, 202);

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = witness_seal::EAlreadyMinted)]
fun rejects_double_mint_by_same_player() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        b"First",
        b"x",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_A);
    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        b"Second attempt",
        b"y",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = witness_seal::EInvalidBattle)]
fun rejects_non_battle_3_mint() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg,
        1, // wrong battle
        1,
        b"Title",
        b"x",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = witness_seal::ETitleTooLong)]
fun rejects_witness_title_over_max_bytes() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    // MAX_TITLE_LEN is 320; 321 'x' bytes should trip the assert.
    let mut bad = vector::empty<u8>();
    let mut i = 0;
    while (i < 321) {
        vector::push_back(&mut bad, 120u8);
        i = i + 1;
    };

    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        bad,
        b"x",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
fun two_different_players_get_increasing_order() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        b"A's seal",
        b"x",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_B);
    witness_seal::mint_witness(
        &mut reg,
        3,
        3,
        b"B's seal",
        b"y",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_B);
    let seal_b = ts::take_from_sender<WitnessSeal>(&sc);
    assert!(witness_seal::mint_order(&seal_b) == 2, 300);
    assert!(!witness_seal::is_first_chronicler(&seal_b), 301);
    ts::return_to_sender(&sc, seal_b);

    assert!(witness_seal::total_minted(&reg) == 2, 400);

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}
