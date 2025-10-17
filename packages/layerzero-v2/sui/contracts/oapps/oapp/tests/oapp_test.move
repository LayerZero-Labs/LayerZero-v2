#[test_only]
module oapp::oapp_test;

use call::call_cap;
use oapp::oapp::{Self, AdminCap, OApp};
use sui::test_scenario::{Self, Scenario};

// === Test Constants ===
const ADMIN: address = @0xa0a0;
const USER: address = @0xb0b0;
const DST_EID: u32 = 2;

// === Test Setup ===

fun setup(): Scenario {
    test_scenario::begin(ADMIN)
}

// === OApp Creation Tests ===

#[test]
fun test_create_oapp() {
    let mut scenario = setup();

    // Create OApp
    scenario.next_tx(ADMIN);
    {
        let call_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        let admin_cap = oapp::create_admin_cap_for_test(test_scenario::ctx(&mut scenario));
        let oapp = oapp::create_oapp_for_test(&call_cap, &admin_cap, test_scenario::ctx(&mut scenario));

        // Verify initial state
        assert!(oapp.admin_cap() == object::id_address(&admin_cap), 0);
        assert!(oapp.oapp_cap_id() == call_cap.id(), 1);

        // Clean up - need to consume the oapp
        oapp::share_oapp_for_test(oapp);
        transfer::public_transfer(call_cap, ADMIN);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_share_oapp() {
    let mut scenario = setup();

    // Create and share OApp
    scenario.next_tx(ADMIN);
    {
        let call_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        let admin_cap = oapp::create_admin_cap_for_test(test_scenario::ctx(&mut scenario));
        let oapp = oapp::create_oapp_for_test(&call_cap, &admin_cap, test_scenario::ctx(&mut scenario));
        oapp::share_oapp_for_test(oapp);
        transfer::public_transfer(call_cap, ADMIN);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Verify it's shared
    scenario.next_tx(USER);
    assert!(test_scenario::has_most_recent_shared<OApp>(), 0);

    test_scenario::end(scenario);
}

#[test]
fun test_transfer_admin_cap() {
    let mut scenario = setup();

    // Create OApp
    scenario.next_tx(ADMIN);
    {
        let call_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        let admin_cap = oapp::create_admin_cap_for_test(test_scenario::ctx(&mut scenario));
        let oapp = oapp::create_oapp_for_test(&call_cap, &admin_cap, test_scenario::ctx(&mut scenario));

        oapp::share_oapp_for_test(oapp);
        transfer::public_transfer(call_cap, ADMIN);
        transfer::public_transfer(admin_cap, USER); // Transfer admin cap to USER
    };

    // Verify USER received the admin cap
    scenario.next_tx(USER);
    assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario), 0);

    test_scenario::end(scenario);
}

// === View Functions Tests ===

#[test]
fun test_view_functions() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let call_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        let admin_cap = oapp::create_admin_cap_for_test(test_scenario::ctx(&mut scenario));
        let oapp = oapp::create_oapp_for_test(&call_cap, &admin_cap, test_scenario::ctx(&mut scenario));

        // Test view functions
        assert!(oapp.admin_cap() == object::id_address(&admin_cap), 0);
        assert!(oapp.oapp_cap_id() == call_cap.id(), 1);

        // Test peer functions when no peer is set
        assert!(!oapp.has_peer(DST_EID), 3);

        // Clean up - need to consume the oapp
        oapp::share_oapp_for_test(oapp);
        transfer::public_transfer(call_cap, ADMIN);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    test_scenario::end(scenario);
}
