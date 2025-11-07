#[test_only]
module oft::pausable_tests;

use oft::pausable;
use iota::{event, test_scenario};

const ALICE: address = @0xa11ce;

#[test]
fun test_pause_operations_and_events() {
    let scenario = test_scenario::begin(ALICE);
    let mut pausable = pausable::new();

    // Initially not paused
    assert!(!pausable.is_paused(), 0);

    // Pause the operations
    pausable.set_pause(true);

    // Should now be paused
    assert!(pausable.is_paused(), 1);

    // Check that pause event was emitted
    let events_after_pause = event::events_by_type<pausable::PausedSetEvent>();
    assert!(events_after_pause.length() == 1, 2);

    // Unpause the operations
    pausable.set_pause(false);

    // Should now be unpaused
    assert!(!pausable.is_paused(), 3);

    // Check that both pause and unpause events were emitted (total of 2)
    let events_after_unpause = event::events_by_type<pausable::PausedSetEvent>();
    assert!(events_after_unpause.length() == 2, 4);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = pausable::EPaused)]
fun test_assert_not_paused_fails_when_paused() {
    let mut pausable = pausable::new();
    pausable.set_pause(true);

    // This should fail with EPaused error code
    pausable.assert_not_paused();
}

#[test]
#[expected_failure(abort_code = pausable::EPauseUnchanged)]
fun test_set_pause_same_state_fails() {
    let mut pausable = pausable::new();

    // Initially not paused, trying to set to false again should fail
    pausable.set_pause(false);
}

#[test]
#[expected_failure(abort_code = pausable::EPauseUnchanged)]
fun test_set_pause_same_state_true_fails() {
    let mut pausable = pausable::new();

    // First set to true
    pausable.set_pause(true);

    // Trying to set to true again should fail
    pausable.set_pause(true);
}
