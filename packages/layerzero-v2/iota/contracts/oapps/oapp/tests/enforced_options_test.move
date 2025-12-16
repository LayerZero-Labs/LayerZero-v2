#[test_only]
module oapp::enforced_options_test;

use oapp::enforced_options;
use iota::{test_scenario, test_utils};

// === Test Constants ===
const ADMIN: address = @0xa0a0;
const OAPP_ADDRESS: address = @0xb1b1;
const DST_EID_1: u32 = 1;
const DST_EID_2: u32 = 2;
const MSG_TYPE_1: u16 = 1;
const MSG_TYPE_2: u16 = 2;

// Valid Type 3 options (starts with 0x0003)
const VALID_OPTIONS_1: vector<u8> = x"00030000000000000000000000000000001234";
const VALID_OPTIONS_2: vector<u8> = x"00030000000000000000000000000000005678";
const VALID_OPTIONS_3: vector<u8> = x"00030000000000000000000000000000009ABC";

// Combined options (VALID_OPTIONS_2 + remainder of VALID_OPTIONS_1)
const COMBINED_OPTIONS: vector<u8> = x"000300000000000000000000000000000056780000000000000000000000000000001234";

// Invalid options
const INVALID_OPTIONS_WRONG_TYPE: vector<u8> = x"00020000000000000000000000000000001234"; // Type 2 instead of 3
const INVALID_OPTIONS_TOO_SHORT: vector<u8> = x"00"; // Too short

// === Tests ===

#[test]
fun test_set_enforced_options() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set enforced options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);

        // Verify options are set
        let retrieved = enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_1);
        let expected = VALID_OPTIONS_1;
        assert!(retrieved == expected, 0);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_set_multiple_enforced_options() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set multiple enforced options for different eids and msg types
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_2, VALID_OPTIONS_2);
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_2, MSG_TYPE_1, VALID_OPTIONS_3);

        // Verify all options are set correctly
        let expected1 = VALID_OPTIONS_1;
        let expected2 = VALID_OPTIONS_2;
        let expected3 = VALID_OPTIONS_3;
        assert!(enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_1) == expected1, 0);
        assert!(enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_2) == expected2, 1);
        assert!(enforced_options::get_enforced_options(&enforced, DST_EID_2, MSG_TYPE_1) == expected3, 2);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_update_enforced_options() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set initial options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);
        let expected_initial = VALID_OPTIONS_1;
        assert!(enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_1) == expected_initial, 0);

        // Update options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_2);
        let expected_updated = VALID_OPTIONS_2;
        assert!(enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_1) == expected_updated, 1);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oapp::enforced_options::EEnforcedOptionsNotFound)]
fun test_get_enforced_options_not_found() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Try to get options that don't exist - should abort
        let _ = enforced_options::get_enforced_options(&enforced, DST_EID_1, MSG_TYPE_1);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_combine_options_with_enforced() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set enforced options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_2);

        // Combine with extra options
        let combined = enforced_options::combine_options(&enforced, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);
        assert!(combined == COMBINED_OPTIONS, 0);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_combine_options_no_enforced() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Combine when no enforced options exist - should return extra options
        let result = enforced_options::combine_options(&enforced, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);
        assert!(result == VALID_OPTIONS_1, 0);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_combine_options_empty_extra() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set enforced options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);

        // Combine with empty extra options - should return enforced options
        let result = enforced_options::combine_options(&enforced, DST_EID_1, MSG_TYPE_1, vector::empty());
        assert!(result == VALID_OPTIONS_1, 0);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_combine_options_both_empty() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Combine when both are empty - should return empty
        let result = enforced_options::combine_options(&enforced, DST_EID_1, MSG_TYPE_1, vector::empty());
        assert!(result == vector::empty(), 0);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oapp::enforced_options::EInvalidOptionsType)]
fun test_set_enforced_options_invalid_type() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Try to set options with wrong type - should abort
        enforced_options::set_enforced_options(
            &mut enforced,
            OAPP_ADDRESS,
            DST_EID_1,
            MSG_TYPE_1,
            INVALID_OPTIONS_WRONG_TYPE,
        );

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oapp::enforced_options::EInvalidOptionsLength)]
fun test_set_enforced_options_too_short() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Try to set options that are too short - should abort
        enforced_options::set_enforced_options(
            &mut enforced,
            OAPP_ADDRESS,
            DST_EID_1,
            MSG_TYPE_1,
            INVALID_OPTIONS_TOO_SHORT,
        );

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oapp::enforced_options::EInvalidOptionsType)]
fun test_combine_options_invalid_extra() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut enforced = enforced_options::new(test_scenario::ctx(&mut scenario));

        // Set valid enforced options
        enforced_options::set_enforced_options(&mut enforced, OAPP_ADDRESS, DST_EID_1, MSG_TYPE_1, VALID_OPTIONS_1);

        // Try to combine with invalid extra options - should abort
        let _ = enforced_options::combine_options(&enforced, DST_EID_1, MSG_TYPE_1, INVALID_OPTIONS_WRONG_TYPE);

        test_utils::destroy(enforced);
    };

    test_scenario::end(scenario);
}
