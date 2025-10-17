/// Pausable Module
///
/// This module provides emergency pause functionality for OFT operations.
/// When paused, critical operations like send/receive transfers are blocked,
/// allowing administrators to halt operations during emergencies or maintenance.
module oft::pausable;

use sui::event;

// === Errors ===

const EPaused: u64 = 1;
const EPauseUnchanged: u64 = 2;

// === Structs ===

/// Pausable state container that can be embedded in OFT structs.
public struct Pausable has drop, store {
    /// Current pause state - true means operations are suspended
    paused: bool,
}

// === Events ===

public struct PausedSetEvent has copy, drop {
    /// New pause state - true indicates operations are suspended, false indicates normal operation
    paused: bool,
}

// === Creation ===

/// Creates a new Pausable instance in the unpaused state.
public(package) fun new(): Pausable {
    Pausable { paused: false }
}

// === Management Functions ===

/// Updates the pause state and emits a state change event.
///
/// **Parameters**:
/// * `paused` - New pause state to set
public(package) fun set_pause(self: &mut Pausable, paused: bool) {
    assert!(self.paused != paused, EPauseUnchanged);
    self.paused = paused;
    event::emit(PausedSetEvent { paused });
}

// === View Functions ===

/// Returns the current pause state.
public(package) fun is_paused(self: &Pausable): bool {
    self.paused
}

/// Asserts that operations are not currently paused.
public(package) fun assert_not_paused(self: &Pausable) {
    assert!(!self.paused, EPaused);
}
