#[test_only]
module oapp::oapp_peer_test;

use oapp::oapp_peer;
use iota::{test_scenario, test_utils};
use utils::bytes32;

// === Test Constants ===
const ADMIN: address = @0xa0a0;
const OAPP_ADDRESS: address = @0xc1c1;
const PEER_ADDRESS: address = @0xb0b0;
const DST_EID_1: u32 = 1;
const DST_EID_2: u32 = 2;
const DST_EID_3: u32 = 3;

// === Tests ===

#[test]
fun test_set_peer() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut peer = oapp_peer::new(test_scenario::ctx(&mut scenario));
        let peer_addr = bytes32::from_address(PEER_ADDRESS);

        // Initially no peer
        assert!(!oapp_peer::has_peer(&peer, DST_EID_1), 0);

        // Set peer
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_1, peer_addr);

        // Verify peer is set
        assert!(oapp_peer::has_peer(&peer, DST_EID_1), 1);
        assert!(oapp_peer::get_peer(&peer, DST_EID_1) == peer_addr, 2);

        test_utils::destroy(peer);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_set_multiple_peers() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut peer = oapp_peer::new(test_scenario::ctx(&mut scenario));
        let peer_addr_1 = bytes32::from_address(@0x1111);
        let peer_addr_2 = bytes32::from_address(@0x2222);
        let peer_addr_3 = bytes32::from_address(@0x3333);

        // Set multiple peers
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_1, peer_addr_1);
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_2, peer_addr_2);
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_3, peer_addr_3);

        // Verify all peers are set correctly
        assert!(oapp_peer::has_peer(&peer, DST_EID_1), 0);
        assert!(oapp_peer::has_peer(&peer, DST_EID_2), 1);
        assert!(oapp_peer::has_peer(&peer, DST_EID_3), 2);

        assert!(oapp_peer::get_peer(&peer, DST_EID_1) == peer_addr_1, 3);
        assert!(oapp_peer::get_peer(&peer, DST_EID_2) == peer_addr_2, 4);
        assert!(oapp_peer::get_peer(&peer, DST_EID_3) == peer_addr_3, 5);

        test_utils::destroy(peer);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_update_peer() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut peer = oapp_peer::new(test_scenario::ctx(&mut scenario));
        let old_peer_addr = bytes32::from_address(@0x1111);
        let new_peer_addr = bytes32::from_address(@0x2222);

        // Set initial peer
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_1, old_peer_addr);
        assert!(oapp_peer::get_peer(&peer, DST_EID_1) == old_peer_addr, 0);

        // Update peer (using set_peer again should update)
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_1, new_peer_addr);
        assert!(oapp_peer::get_peer(&peer, DST_EID_1) == new_peer_addr, 1);

        test_utils::destroy(peer);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oapp::oapp_peer::EPeerNotFound)]
fun test_get_peer_not_found() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let peer = oapp_peer::new(test_scenario::ctx(&mut scenario));

        // Try to get a peer that doesn't exist - should abort
        let _ = oapp_peer::get_peer(&peer, DST_EID_1);

        test_utils::destroy(peer);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_has_peer() {
    let mut scenario = test_scenario::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        let mut peer = oapp_peer::new(test_scenario::ctx(&mut scenario));

        // Check has_peer returns false for non-existent peers
        assert!(!oapp_peer::has_peer(&peer, DST_EID_1), 0);
        assert!(!oapp_peer::has_peer(&peer, DST_EID_2), 1);

        // Set one peer
        let peer_addr = bytes32::from_address(PEER_ADDRESS);
        oapp_peer::set_peer(&mut peer, OAPP_ADDRESS, DST_EID_1, peer_addr);

        // Verify only DST_EID_1 has peer
        assert!(oapp_peer::has_peer(&peer, DST_EID_1), 2);
        assert!(!oapp_peer::has_peer(&peer, DST_EID_2), 3);

        test_utils::destroy(peer);
    };

    test_scenario::end(scenario);
}
