#[test_only]
module chronicle::chronicle_tests;

use chronicle::chronicle::{Self, Chronicle, ChronicleRegistry};
use sui::clock;
use sui::test_scenario as ts;

const PLAYER_A: address = @0xA11CE;
const PLAYER_B: address = @0xB0B;

#[test]
fun mint_increments_per_battle_counter() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));

    ts::next_tx(&mut sc, PLAYER_A);
    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    chronicle::mint_chronicle(
        &mut reg,
        1,
        1,
        b"The Battle of Lumen Harbor",
        b"Speak with your blade, not your numbers.",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_A);
    let nft = ts::take_from_sender<Chronicle>(&sc);
    assert!(chronicle::battle_id(&nft) == 1, 100);
    assert!(chronicle::hero_id(&nft) == 1, 101);
    assert!(chronicle::rating(&nft) == 0, 102);
    assert!(chronicle::mint_order(&nft) == 1, 103);
    assert!(chronicle::is_first_chronicler(&nft), 104);
    assert!(chronicle::player(&nft) == PLAYER_A, 105);
    ts::return_to_sender(&sc, nft);

    // Second mint by PLAYER_B for the same battle => order = 2, not first.
    ts::next_tx(&mut sc, PLAYER_B);
    chronicle::mint_chronicle(
        &mut reg,
        1,
        2,
        b"80 Against 200",
        b"We held the line.",
        1,
        &clk,
        ts::ctx(&mut sc),
    );

    ts::next_tx(&mut sc, PLAYER_B);
    let nft2 = ts::take_from_sender<Chronicle>(&sc);
    assert!(chronicle::mint_order(&nft2) == 2, 200);
    assert!(!chronicle::is_first_chronicler(&nft2), 201);
    ts::return_to_sender(&sc, nft2);

    // Third mint, but for battle 2 => its own counter starts at 1.
    ts::next_tx(&mut sc, PLAYER_A);
    chronicle::mint_chronicle(
        &mut reg,
        2,
        3,
        b"Sea of Consensus",
        b"The waves remember.",
        2,
        &clk,
        ts::ctx(&mut sc),
    );

    assert!(chronicle::count_for_battle(&reg, 1) == 2, 300);
    assert!(chronicle::count_for_battle(&reg, 2) == 1, 301);
    assert!(chronicle::count_for_battle(&reg, 3) == 0, 302);

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::ETitleTooLong)]
fun rejects_title_over_max_bytes() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    // MAX_TITLE_LEN is 320; 321 'x' bytes should trip the assert.
    let mut bad = vector::empty<u8>();
    let mut i = 0;
    while (i < 321) {
        vector::push_back(&mut bad, 120u8);
        i = i + 1;
    };

    chronicle::mint_chronicle(
        &mut reg,
        1,
        1,
        bad,
        b"ok",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::EInscriptionTooLong)]
fun rejects_inscription_over_max_bytes() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    // MAX_INSCRIPTION_LEN is 200; 201 'y' bytes should trip the assert.
    let mut bad = vector::empty<u8>();
    let mut i = 0;
    while (i < 201) {
        vector::push_back(&mut bad, 121u8);
        i = i + 1;
    };

    chronicle::mint_chronicle(
        &mut reg,
        1,
        1,
        b"Title",
        bad,
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::ETitleEmpty)]
fun rejects_empty_title() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    chronicle::mint_chronicle(
        &mut reg,
        1,
        1,
        b"",
        b"ok",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::EInvalidBattleId)]
fun rejects_battle_id_zero() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    chronicle::mint_chronicle(
        &mut reg,
        0,
        1,
        b"Title",
        b"ok",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::EInvalidHeroId)]
fun rejects_hero_id_zero() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    chronicle::mint_chronicle(
        &mut reg,
        1,
        0,
        b"Title",
        b"ok",
        0,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = chronicle::EInvalidRating)]
fun rejects_rating_above_3() {
    let mut sc = ts::begin(PLAYER_A);
    chronicle::init_for_testing(ts::ctx(&mut sc));
    ts::next_tx(&mut sc, PLAYER_A);

    let mut reg = ts::take_shared<ChronicleRegistry>(&sc);
    let clk = clock::create_for_testing(ts::ctx(&mut sc));

    chronicle::mint_chronicle(
        &mut reg,
        1,
        1,
        b"Title",
        b"ok",
        4,
        &clk,
        ts::ctx(&mut sc),
    );

    clock::destroy_for_testing(clk);
    ts::return_shared(reg);
    ts::end(sc);
}
