#[test_only]
module chronicle::witness_seal_tests;

use chronicle::witness_seal::{Self, WitnessSeal, WitnessRegistry};
use sui::clock;
use sui::test_scenario as ts;

const PLAYER_A: address = @0xA11CE;
const PLAYER_B: address = @0xB0B;

// A long-future expiry so the (unreached) voucher checks in validation tests
// never trip on expiry first.
const FAR_FUTURE_MS: u64 = 9_999_999_999_999;

#[test]
fun mint_witness_happy_path() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    // Bypasses the voucher (the real ed25519 path is exercised off-chain).
    witness_seal::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

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
    assert!(witness_seal::version(&reg) == 1, 203);
    assert!(!witness_seal::is_paused(&reg), 204);

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

    witness_seal::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);
    witness_seal::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

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

    witness_seal::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_B);
    witness_seal::mint_for_testing(&mut reg, 3, &clk, ts::ctx(&mut sc));

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

// ---- Validation tests go through mint_witness; they abort on the field check
// BEFORE the voucher check, so dummy voucher args (empty sig) are never reached.

#[test]
#[expected_failure(abort_code = witness_seal::EInvalidBattle)]
fun rejects_non_battle_3_mint() {
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg, 1, 1, b"Title", b"x", 0,
        0, FAR_FUTURE_MS, vector::empty<u8>(), &clk, ts::ctx(&mut sc),
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

    let mut bad = vector::empty<u8>();
    let mut i = 0;
    while (i < 321) { vector::push_back(&mut bad, 120u8); i = i + 1; };

    witness_seal::mint_witness(
        &mut reg, 3, 3, bad, b"x", 0,
        0, FAR_FUTURE_MS, vector::empty<u8>(), &clk, ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = witness_seal::EAuthorityNotSet)]
fun rejects_mint_when_authority_unset() {
    // Valid fields, but no authority pubkey set => the voucher gate aborts.
    // Proves mint_witness is no longer an open mint.
    let mut sc = ts::begin(PLAYER_A);
    witness_seal::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<WitnessRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    witness_seal::mint_witness(
        &mut reg, 3, 3, b"Valid title", b"ok", 0,
        0, FAR_FUTURE_MS, vector::empty<u8>(), &clk, ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}
