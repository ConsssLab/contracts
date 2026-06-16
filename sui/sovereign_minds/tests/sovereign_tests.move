#[test_only]
module sovereign_minds::sovereign_tests;

use sovereign_minds::sovereign::{Self, SovereignRegistry, AdminCap};
use sui::clock;
use sui::ed25519;
use sui::test_scenario as ts;

// Cross-validation vector produced by play/shared/selftest.mjs (the off-chain
// signer). If this test passes, the Move build_voucher_message produces the
// EXACT bytes the JS signer signed — i.e. the two sides agree byte-for-byte, so
// a real backend voucher will verify on-chain. Regenerate with:
//   cd play && node shared/selftest.mjs   (see section [1])
const TEST_PUBKEY: vector<u8> = x"239f5307e3023fd37fcd6b4e8cec59cb2038c40223a87fbc9a48355626ee6cb3";
const TEST_SIG: vector<u8> = x"32b232173a648abc0aa236978bc911011b4dee82a3349d718ea2b23f48a4d7a2da366fd493498cfe7d95116d1d1227df56ffef53ef9240f418a7e9ef25f55303";

#[test]
fun voucher_crossvalidation_matches_offchain_signer() {
    // Symmetric byte addresses → endianness-agnostic, so the vector is robust.
    let registry_id = @0xabababababababababababababababababababababababababababababababab;
    let player = @0x1111111111111111111111111111111111111111111111111111111111111111;

    let msg = sovereign::build_voucher_message_for_testing(
        registry_id, player, 1, 1, 87, 41234, 12345678901234567, 1893456000000,
    );
    // The on-chain verify accepts the off-chain signature ⇒ identical message bytes.
    assert!(ed25519::ed25519_verify(&TEST_SIG, &TEST_PUBKEY, &msg), 100);

    // Tamper a single attested field (hp 87 → 88): signature must NO LONGER verify.
    let tampered = sovereign::build_voucher_message_for_testing(
        registry_id, player, 1, 1, 88, 41234, 12345678901234567, 1893456000000,
    );
    assert!(!ed25519::ed25519_verify(&TEST_SIG, &TEST_PUBKEY, &tampered), 101);

    // Tamper the score (41234 → 41235): also must fail.
    let tampered2 = sovereign::build_voucher_message_for_testing(
        registry_id, player, 1, 1, 87, 41235, 12345678901234567, 1893456000000,
    );
    assert!(!ed25519::ed25519_verify(&TEST_SIG, &TEST_PUBKEY, &tampered2), 102);
}

#[test]
fun tier_floor_by_rank_upgrade_by_hp() {
    let mut sc = ts::begin(@0xA);
    sovereign::init_for_testing(sc.ctx());
    sc.next_tx(@0xA);
    let mut reg = sc.take_shared<SovereignRegistry>();
    let clock = clock::create_for_testing(sc.ctx());

    // rank 1 (Silver floor) + hp 85 (>=80) ⇒ upgrade ⇒ Gold(3).
    let d = sovereign::mint_for_testing(&mut reg, 1, 1, 85, 1000, b"blob", &clock, sc.ctx());
    assert!(sovereign::tier(&d) == 3, 1);
    assert!(sovereign::score_milli(&d) == 1000, 2);
    assert!(sovereign::is_first_sovereign(&d), 3);
    sovereign::destroy_for_testing(d);

    // rank 2 (Silver floor) + hp 50 + tiny score ⇒ no upgrade ⇒ Silver(2).
    let d2 = sovereign::mint_for_testing(&mut reg, 1, 1, 50, 1000, b"blob", &clock, sc.ctx());
    assert!(sovereign::tier(&d2) == 2, 4);
    sovereign::destroy_for_testing(d2);

    // rank 101 (Bronze floor) + hp 50 ⇒ Bronze(1).
    sovereign::set_count_for_testing(&mut reg, 1, 100);
    let d3 = sovereign::mint_for_testing(&mut reg, 1, 1, 50, 1000, b"blob", &clock, sc.ctx());
    assert!(sovereign::tier(&d3) == 1, 5);
    sovereign::destroy_for_testing(d3);

    // rank 301 (Normal floor) + hp 50 ⇒ Normal(0).
    sovereign::set_count_for_testing(&mut reg, 1, 300);
    let d4 = sovereign::mint_for_testing(&mut reg, 1, 1, 50, 1000, b"blob", &clock, sc.ctx());
    assert!(sovereign::tier(&d4) == 0, 6);
    sovereign::destroy_for_testing(d4);

    clock::destroy_for_testing(clock);
    ts::return_shared(reg);
    sc.end();
}

#[test]
fun tier_upgrade_by_score_when_threshold_lowered() {
    let mut sc = ts::begin(@0xA);
    sovereign::init_for_testing(sc.ctx());
    sc.next_tx(@0xA);
    let mut reg = sc.take_shared<SovereignRegistry>();
    let admin = sc.take_from_sender<AdminCap>();
    let clock = clock::create_for_testing(sc.ctx());

    // Lower the score-upgrade threshold so a high score alone earns the bump.
    sovereign::set_score_upgrade_threshold(&admin, &mut reg, 500);
    // rank 1 (Silver floor), hp 40 (<80) but score 1000 (>=500) ⇒ upgrade ⇒ Gold(3).
    let d = sovereign::mint_for_testing(&mut reg, 1, 1, 40, 1000, b"blob", &clock, sc.ctx());
    assert!(sovereign::tier(&d) == 3, 1);
    sovereign::destroy_for_testing(d);

    clock::destroy_for_testing(clock);
    sc.return_to_sender(admin);
    ts::return_shared(reg);
    sc.end();
}

#[test]
#[expected_failure]
fun rank_cap_blocks_1001st() {
    let mut sc = ts::begin(@0xA);
    sovereign::init_for_testing(sc.ctx());
    sc.next_tx(@0xA);
    let mut reg = sc.take_shared<SovereignRegistry>();
    let clock = clock::create_for_testing(sc.ctx());

    // 1000 already minted ⇒ the 1001st aborts (ENoNFT).
    sovereign::set_count_for_testing(&mut reg, 1, 1000);
    let d = sovereign::mint_for_testing(&mut reg, 1, 1, 90, 1000, b"blob", &clock, sc.ctx());
    sovereign::destroy_for_testing(d); // unreachable

    clock::destroy_for_testing(clock);
    ts::return_shared(reg);
    sc.end();
}
