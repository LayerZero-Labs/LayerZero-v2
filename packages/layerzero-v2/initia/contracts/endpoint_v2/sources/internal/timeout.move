/// The Timeout configuration is used when migrating the Receive message library, and it defines the window of blocks
/// that the prior library will be allowed to receive messages. When the grace period expires, messages from the prior
/// library will be rejected.
module endpoint_v2::timeout {
    use std::block::get_current_block_height;

    friend endpoint_v2::msglib_manager;

    friend endpoint_v2::endpoint;

    #[test_only]
    friend endpoint_v2::msglib_manager_tests;

    struct Timeout has store, drop, copy {
        // The block number at which the grace period expires
        expiry: u64,
        // The address of the fallback library
        lib: address,
    }

    /// Create a new timeout configuration
    public(friend) fun new_timeout_from_grace_period(grace_period_in_blocks: u64, lib: address): Timeout {
        let expiry = get_current_block_height() + grace_period_in_blocks;
        Timeout { expiry, lib }
    }

    /// Create a new timeout configuration using an expiry block number
    public(friend) fun new_timeout_from_expiry(expiry: u64, lib: address): Timeout {
        Timeout { expiry, lib }
    }

    public(friend) fun unpack_timeout(timeout: Timeout): (u64, address) {
        (timeout.expiry, timeout.lib)
    }

    /// Check if the timeout is active
    /// A timeout is active so long as the current block height is less than the expiry block number
    public(friend) fun is_active(self: &Timeout): bool {
        self.expiry > get_current_block_height()
    }

    /// Get the address of the fallback library
    public(friend) fun get_library(self: &Timeout): address {
        self.lib
    }

    /// Get the expiry block number
    public(friend) fun get_expiry(self: &Timeout): u64 {
        self.expiry
    }
}