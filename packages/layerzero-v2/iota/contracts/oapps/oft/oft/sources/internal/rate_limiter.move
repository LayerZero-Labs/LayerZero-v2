/// Rate Limiter Implementation for OFT
///
/// This module provides rate limiting functionality for cross-chain token transfers,
/// implementing a sliding window rate limiter that decays linearly over time.
module oft::rate_limiter;

use std::u64;
use iota::{clock::Clock, event, table::{Self, Table}};
use utils::table_ext;

// === Errors ===

const EExceededRateLimit: u64 = 1;
const EInvalidTimestamp: u64 = 2;
const EInvalidWindowSeconds: u64 = 3;
const ESameValue: u64 = 4;

// === Structs ===

/// Rate limiter containing all rate limits indexed by endpoint ID
public struct RateLimiter has store {
    /// Direction of the rate limit
    direction: Direction,
    /// Table mapping endpoint IDs to their rate limit configurations
    rate_limit_by_eid: Table<u32, RateLimit>,
}

/// Rate limit configuration for a specific endpoint
public struct RateLimit has copy, drop, store {
    /// Maximum amount that can be in-flight within the time window
    limit: u64,
    /// Time window in seconds for the rate limit
    window_seconds: u64,
    /// Amount in-flight at the last checkpoint
    in_flight_on_last_update: u64,
    /// Timestamp of the last update in seconds
    last_update: u64,
}

public enum Direction has copy, drop, store {
    Inbound,
    Outbound,
}

// === Events ===

/// Emitted when a new rate limit is set for an endpoint
public struct RateLimitSetEvent has copy, drop {
    /// Direction of the rate limit
    direction: Direction,
    /// Remote endpoint ID
    eid: u32,
    /// Rate limit amount
    limit: u64,
    /// Time window in seconds
    window_seconds: u64,
}

/// Emitted when an existing rate limit is updated
public struct RateLimitUpdatedEvent has copy, drop {
    /// Direction of the rate limit
    direction: Direction,
    /// Remote endpoint ID
    eid: u32,
    /// New rate limit amount
    limit: u64,
    /// New time window in seconds
    window_seconds: u64,
}

/// Emitted when a rate limit is removed
public struct RateLimitUnsetEvent has copy, drop {
    /// Direction of the rate limit
    direction: Direction,
    /// Remote endpoint ID for which rate limit was removed
    eid: u32,
}

// === Creation ===

/// Creates a new rate limiter
public(package) fun create(inbound: bool, ctx: &mut tx_context::TxContext): RateLimiter {
    RateLimiter {
        rate_limit_by_eid: table::new(ctx),
        direction: if (inbound) Direction::Inbound else Direction::Outbound,
    }
}

// === Rate Limit Core Functions ===

/// Consume rate limit capacity for a given EID or abort if the capacity is exceeded
public(package) fun try_consume_rate_limit_capacity(self: &mut RateLimiter, eid: u32, amount: u64, clock: &Clock) {
    if (!self.has_rate_limit(eid)) return;

    self.checkpoint_rate_limit_in_flight(eid, clock);
    let rate_limit = &mut self.rate_limit_by_eid[eid];
    assert!(rate_limit.in_flight_on_last_update + amount <= rate_limit.limit, EExceededRateLimit);
    rate_limit.in_flight_on_last_update = rate_limit.in_flight_on_last_update + amount;
}

/// Release rate limit capacity for a given EID
/// This is used when wanting to rate limit by net inflow - outflow
/// This will release the capacity back to the rate limit up to the limit itself
public(package) fun release_rate_limit_capacity(self: &mut RateLimiter, eid: u32, amount: u64, clock: &Clock) {
    if (!self.has_rate_limit(eid)) return;

    self.checkpoint_rate_limit_in_flight(eid, clock);
    let rate_limit = &mut self.rate_limit_by_eid[eid];
    if (amount >= rate_limit.in_flight_on_last_update) {
        rate_limit.in_flight_on_last_update = 0;
    } else {
        rate_limit.in_flight_on_last_update = rate_limit.in_flight_on_last_update - amount;
    }
}

// === Rate Limit Management ===

/// Set the rate limit and the window at the current timestamp
/// The capacity of the rate limit increases by limit/window_s until it reaches the limit and stays there
public(package) fun set_rate_limit(self: &mut RateLimiter, eid: u32, limit: u64, window_seconds: u64, clock: &Clock) {
    assert!(window_seconds > 0, EInvalidWindowSeconds);
    // If the rate limit is already set, checkpoint the in-flight amount before updating the rate limit
    if (self.has_rate_limit(eid)) {
        let (prior_limit, prior_window_seconds) = self.rate_limit_config(eid);
        assert!(limit != prior_limit || window_seconds != prior_window_seconds, ESameValue);

        // Checkpoint the in-flight amount before updating the rate settings. If this is not saved, it could change
        // the in-flight calculation amount retroactively
        self.checkpoint_rate_limit_in_flight(eid, clock);

        let rate_limit = &mut self.rate_limit_by_eid[eid];
        rate_limit.limit = limit;
        rate_limit.window_seconds = window_seconds;
        event::emit(RateLimitUpdatedEvent { direction: self.direction, eid, limit, window_seconds });
    } else {
        table_ext::upsert!(
            &mut self.rate_limit_by_eid,
            eid,
            RateLimit { limit, window_seconds, in_flight_on_last_update: 0, last_update: timestamp_seconds(clock) },
        );
        event::emit(RateLimitSetEvent { direction: self.direction, eid, limit, window_seconds });
    }
}

/// Unset the rate limit for a given EID
public(package) fun unset_rate_limit(self: &mut RateLimiter, eid: u32) {
    assert!(self.has_rate_limit(eid), ESameValue);
    self.rate_limit_by_eid.remove(eid);
    event::emit(RateLimitUnsetEvent { direction: self.direction, eid });
}

// === Drop Function ===

public(package) fun drop(self: RateLimiter) {
    let RateLimiter { rate_limit_by_eid, .. } = self;
    rate_limit_by_eid.drop();
}

// === View Functions ===

/// Get the rate limit and window (in seconds) for a given EID
public(package) fun rate_limit_config(self: &RateLimiter, eid: u32): (u64, u64) {
    if (!self.has_rate_limit(eid)) {
        (0, 0)
    } else {
        let rate_limit = &self.rate_limit_by_eid[eid];
        (rate_limit.limit, rate_limit.window_seconds)
    }
}

/// Get the in-flight amount for a given EID at present
public(package) fun in_flight(self: &RateLimiter, eid: u32, clock: &Clock): u64 {
    if (!self.has_rate_limit(eid)) {
        0
    } else {
        let rate_limit = &self.rate_limit_by_eid[eid];
        let timestamp = timestamp_seconds(clock);
        assert!(timestamp >= rate_limit.last_update, EInvalidTimestamp);
        // If the timestamp is greater than the last update, calculate the decayed in-flight amount
        let elapsed = timestamp - rate_limit.last_update;
        let decay = ((((elapsed as u128) * (rate_limit.limit as u128)) / (rate_limit.window_seconds as u128)) as u64);

        // Ensure the decayed in-flight amount is not negative
        if (decay < rate_limit.in_flight_on_last_update) {
            rate_limit.in_flight_on_last_update - decay
        } else {
            0
        }
    }
}

/// Calculate the spare rate limit capacity for a given EID at present
public(package) fun rate_limit_capacity(self: &RateLimiter, eid: u32, clock: &Clock): u64 {
    if (!self.has_rate_limit(eid)) {
        u64::max_value!()
    } else {
        let rate_limit = &self.rate_limit_by_eid[eid];
        let current_in_flight = self.in_flight(eid, clock);
        if (rate_limit.limit > current_in_flight) {
            rate_limit.limit - current_in_flight
        } else {
            0
        }
    }
}

// === Internal Functions ===

/// Checkpoint the in-flight amount for a given EID for the provided timestamp
/// This should be called whenever there is a change in rate limit or before consuming rate limit capacity
fun checkpoint_rate_limit_in_flight(self: &mut RateLimiter, eid: u32, clock: &Clock) {
    let inflight = self.in_flight(eid, clock);
    let rate_limit = &mut self.rate_limit_by_eid[eid];
    rate_limit.in_flight_on_last_update = inflight;
    rate_limit.last_update = timestamp_seconds(clock);
}

/// Check if a rate limit is set for a given EID
fun has_rate_limit(self: &RateLimiter, eid: u32): bool {
    self.rate_limit_by_eid.contains(eid)
}

/// Convert clock timestamp from milliseconds to seconds
fun timestamp_seconds(clock: &Clock): u64 {
    clock.timestamp_ms() / 1000
}
