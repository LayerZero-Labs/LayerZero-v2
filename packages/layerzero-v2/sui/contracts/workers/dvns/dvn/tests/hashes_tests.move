#[test_only]
module dvn::hashes_tests;

use dvn::hashes;
use ptb_move_call::{argument, move_call};
use std::{ascii, bcs, type_name};
use utils::bytes32;

const VID: u32 = 1;
const EXPIRATION: u64 = 2000;

#[test]
fun test_get_function_signature() {
    assert!(hashes::get_function_signature(b"verify") == x"7c40a351", 0);
    assert!(hashes::get_function_signature(b"set_dvn_signer") == x"1372c8d1", 1);
    assert!(hashes::get_function_signature(b"set_quorum") == x"17b7ccf9", 2);
    assert!(hashes::get_function_signature(b"set_allowlist") == x"934ff7eb", 3);
    assert!(hashes::get_function_signature(b"set_denylist") == x"8442b40b", 4);
    assert!(hashes::get_function_signature(b"quorum_change_admin") == x"73028773", 5);
    assert!(hashes::get_function_signature(b"set_pause") == x"de50b5a3", 6);
}

#[test]
fun test_create_verify_hash() {
    // Test params
    let packet_header =
        x"010000000000000001000000010000000000000000000000000000000000000000000000000000000000009099000000010000000000000000000000000000000000000000000000000000000000009099";
    let payload_hash = x"cc35f70cc84269e2bfe02824b3d69e4120e6a58302a8129c4e11d9d9777a38c0";
    let confirmations = 10;
    let target = @0x0000000000000000000000000000000000000000000000000000000000009005;
    // Expected results
    let expected_payload =
        x"7c40a351010000000000000001000000010000000000000000000000000000000000000000000000000000000000009099000000010000000000000000000000000000000000000000000000000000000000009099cc35f70cc84269e2bfe02824b3d69e4120e6a58302a8129c4e11d9d9777a38c0000000000000000a00000000000000000000000000000000000000000000000000000000000090050000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"e3e8219995b9d75e7748415b6d54235f1d1cbec86f12d6602f423b7b20353799");
    assert!(
        hashes::build_verify_payload(
            packet_header,
            payload_hash,
            confirmations,
            target,
            VID,
            EXPIRATION,
        ) == expected_payload,
        0,
    );
    assert!(
        hashes::create_verify_hash(
            packet_header,
            payload_hash,
            confirmations,
            target,
            VID,
            EXPIRATION,
        ) == expected_hash,
        1,
    );
}

#[test]
fun test_create_set_quorum_hash() {
    // Test params
    let quorum = 2;
    // Expected results
    let expected_payload = x"17b7ccf900000000000000020000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"3064e840a7183166bb439dfb1de0f6befc2e1731efcbb90cc6178b6b42cf3584");
    assert!(hashes::build_set_quorum_payload(quorum, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_set_quorum_hash(quorum, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_set_dvn_signer_hash() {
    // Test params
    let signer =
        x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
    let active = true;
    // Expected results
    let expected_payload =
        x"1372c8d1505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d010000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"ad2262753ab5dab4d29c2437dd09d5bc6bdb4632e781d424f031d5cd5970728b");
    assert!(hashes::build_set_dvn_signer_payload(signer, active, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_set_dvn_signer_hash(signer, active, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_set_allowlist_hash() {
    // Test params
    let oapp = @0x0000000000000000000000000000000000000000000000000000000000002704;
    let allowed = true;
    // Expected results
    let expected_payload =
        x"934ff7eb0000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"d418cb1c18cfd5d3fc1fbdac34a9d71fb4b56a8f2d074e36d497c8e0489c7a15");
    assert!(hashes::build_set_allowlist_payload(oapp, allowed, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_set_allowlist_hash(oapp, allowed, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_set_denylist_hash() {
    // Test params
    let oapp = @0x0000000000000000000000000000000000000000000000000000000000002704;
    let denied = true;
    // Expected results
    let expected_payload =
        x"8442b40b0000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"67f702d40c8e4bd7c2d59cc2d772b0a8c2398a08336176f38118fd0f33704817");
    assert!(hashes::build_set_denylist_payload(oapp, denied, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_set_denylist_hash(oapp, denied, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_quorum_change_admin_hash() {
    // Test params
    let admin = @0x0000000000000000000000000000000000000000000000000000000000002704;
    let active = true;
    // Expected results
    let expected_payload =
        x"730287730000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"c8ee741967867d5a99e739baa2a57c8b480a438855a4fc0d7b5ea2e28a8deaa5");
    assert!(hashes::build_quorum_change_admin_payload(admin, active, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_quorum_change_admin_hash(admin, active, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_set_pause_hash() {
    // Test params
    let paused = true;
    // Expected results
    let expected_payload = x"de50b5a3010000000100000000000007d0";
    let expected_hash = bytes32::from_bytes(x"8195d6123fd38c621bc4b41cb598417adbf0f1e18d1b0268cd2f2fc522df588e");
    assert!(hashes::build_set_pause_payload(paused, VID, EXPIRATION) == expected_payload, 0);
    assert!(hashes::create_set_pause_hash(paused, VID, EXPIRATION) == expected_hash, 1);
}

#[test]
fun test_create_set_ptb_builder_move_calls_hash_different_move_calls() {
    let target_ptb_builder = @0x1234567890abcdef;

    // Create first set of MoveCall objects
    let get_fee_arg1 = argument::create_pure(bcs::to_bytes(&ascii::string(b"DVN1")));
    let get_fee_arg2 = argument::create_object(@0x123);
    let get_fee_args1 = vector[get_fee_arg1, get_fee_arg2];
    let get_fee_type_args1 = vector[type_name::get<u64>()];

    let get_fee_move_call1 = move_call::create(
        @0x1234567890abcdef,
        ascii::string(b"fee_module"),
        ascii::string(b"calculate_fee"),
        get_fee_args1,
        get_fee_type_args1,
        true,
        vector[bytes32::zero_bytes32()],
    );
    let get_fee_move_calls1 = vector[get_fee_move_call1];

    let assign_job_arg1 = argument::create_pure(bcs::to_bytes(&100u64));
    let assign_job_arg2 = argument::create_nested_result(0, 1);
    let assign_job_args1 = vector[assign_job_arg1, assign_job_arg2];

    let assign_job_move_call1 = move_call::create(
        @0xabcdef1234567890,
        ascii::string(b"job_module"),
        ascii::string(b"assign_job"),
        assign_job_args1,
        vector[],
        false,
        vector[],
    );
    let assign_job_move_calls1 = vector[assign_job_move_call1];

    // Create second set of MoveCall objects (different from first)
    let get_fee_arg3 = argument::create_pure(bcs::to_bytes(&ascii::string(b"DVN2"))); // Different string
    let get_fee_arg4 = argument::create_object(@0x456); // Different object address
    let get_fee_args2 = vector[get_fee_arg3, get_fee_arg4];
    let get_fee_type_args2 = vector[type_name::get<u128>()]; // Different type

    let get_fee_move_call2 = move_call::create(
        @0x1234567890abcdef,
        ascii::string(b"fee_module"),
        ascii::string(b"calculate_fee"),
        get_fee_args2,
        get_fee_type_args2,
        true,
        vector[bytes32::zero_bytes32()],
    );
    let get_fee_move_calls2 = vector[get_fee_move_call2];

    let assign_job_arg3 = argument::create_pure(bcs::to_bytes(&200u64)); // Different value
    let assign_job_arg4 = argument::create_nested_result(1, 2); // Different indices
    let assign_job_args2 = vector[assign_job_arg3, assign_job_arg4];

    let assign_job_move_call2 = move_call::create(
        @0xabcdef1234567890,
        ascii::string(b"job_module"),
        ascii::string(b"assign_job"),
        assign_job_args2,
        vector[],
        false,
        vector[],
    );
    let assign_job_move_calls2 = vector[assign_job_move_call2];

    // Generate hashes for both sets
    let hash1 = hashes::create_set_ptb_builder_move_calls_hash(
        target_ptb_builder,
        get_fee_move_calls1,
        assign_job_move_calls1,
        VID,
        EXPIRATION,
    );

    let hash2 = hashes::create_set_ptb_builder_move_calls_hash(
        target_ptb_builder,
        get_fee_move_calls2,
        assign_job_move_calls2,
        VID,
        EXPIRATION,
    );

    // Verify that different MoveCall vectors produce different hashes
    assert!(hash1 != hash2, 0);
}
