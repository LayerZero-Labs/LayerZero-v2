/// ExecutorType module provides core types and structures for Executor configuration
module executor::executor_type;

// === Structs ===

/// Destination configuration stored in state
public struct DstConfig has copy, drop, store {
    /// Base gas for lz_receive operations
    lz_receive_base_gas: u64,
    /// Base gas for lz_compose operations
    lz_compose_base_gas: u64,
    /// Multiplier in basis points for fee calculation
    multiplier_bps: u16,
    /// Floor margin in USD with precision
    floor_margin_usd: u128,
    /// Native token cap for operations
    native_cap: u128,
}

// === Constructor Functions ===

/// Create a new DstConfig
public fun create_dst_config(
    lz_receive_base_gas: u64,
    lz_compose_base_gas: u64,
    multiplier_bps: u16,
    floor_margin_usd: u128,
    native_cap: u128,
): DstConfig {
    DstConfig { lz_receive_base_gas, lz_compose_base_gas, multiplier_bps, floor_margin_usd, native_cap }
}

// === Getter Functions ===

public use fun dst_config_lz_receive_base_gas as DstConfig.lz_receive_base_gas;

/// Get lz_receive_base_gas from DstConfig
public fun dst_config_lz_receive_base_gas(config: &DstConfig): u64 {
    config.lz_receive_base_gas
}

public use fun dst_config_lz_compose_base_gas as DstConfig.lz_compose_base_gas;

/// Get lz_compose_base_gas from DstConfig
public fun dst_config_lz_compose_base_gas(config: &DstConfig): u64 {
    config.lz_compose_base_gas
}

public use fun dst_config_multiplier_bps as DstConfig.multiplier_bps;

/// Get multiplier BPS from DstConfig
public fun dst_config_multiplier_bps(config: &DstConfig): u16 {
    config.multiplier_bps
}

public use fun dst_config_floor_margin_usd as DstConfig.floor_margin_usd;

/// Get floor margin USD from DstConfig
public fun dst_config_floor_margin_usd(config: &DstConfig): u128 {
    config.floor_margin_usd
}

public use fun dst_config_native_cap as DstConfig.native_cap;

/// Get native cap from DstConfig
public fun dst_config_native_cap(config: &DstConfig): u128 {
    config.native_cap
}
