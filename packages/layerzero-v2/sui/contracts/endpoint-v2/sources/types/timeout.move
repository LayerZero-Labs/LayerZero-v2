/// Timeout mechanism for message library transitions in endpoint v2.
/// Used by the message library manager to handle graceful transitions when switching receive libraries.
/// Allows the previous receive library to continue processing in-flight messages during a grace period.
module endpoint_v2::timeout;

use sui::clock::Clock;

// === Structs ===

/// Timeout configuration for message library fallback during transitions.
/// When switching from one receive library to another, this allows the old library
/// to continue processing messages that were already in transit for a specified grace period.
/// A timeout for a message-lib fallback.
public struct Timeout has copy, drop, store {
    // Unix timestamp (in seconds) when the grace period expires
    expiry: u64,
    // Capability address of the previous library that can still process messages during the grace period
    fallback_lib: address,
}

// === Creation ===

/// Creates a new Timeout with a specific expiry timestamp in seconds and fallback library.
public(package) fun create(expiry: u64, fallback_lib: address): Timeout {
    Timeout { expiry, fallback_lib }
}

/// Creates a new Timeout with a grace period from the current time in seconds.
/// The expiry is calculated as current time + grace period, providing a more convenient
/// way to set timeouts relative to when the library transition occurs.
public(package) fun create_with_grace_period(grace_period: u64, fallback_lib: address, clock: &Clock): Timeout {
    Timeout { expiry: current_time_in_seconds!(clock) + grace_period, fallback_lib }
}

// === Getters ===

/// Returns the expiry timestamp (in seconds) when the timeout grace period ends.
public fun expiry(self: &Timeout): u64 {
    self.expiry
}

/// Returns the capability address of the fallback library that can process messages during the grace period.
public fun fallback_lib(self: &Timeout): address {
    self.fallback_lib
}

/// Checks if the timeout has expired based on the current time.
/// Returns true if the grace period has ended and the fallback library should no longer be used.
public fun is_expired(self: &Timeout, clock: &Clock): bool {
    self.expiry <= current_time_in_seconds!(clock)
}

// === Helper ===

/// Macro to convert clock timestamp from milliseconds to seconds.
/// Sui's clock provides time in milliseconds, but timeouts are stored in seconds for efficiency.
macro fun current_time_in_seconds($clock: &Clock): u64 {
    let clock = $clock;
    clock.timestamp_ms() / 1000
}
