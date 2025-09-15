/// OApp ULN Config Module
///
/// This module provides configuration management for OApp-specific ULN settings.
/// It allows OApps to selectively override default ULN configurations while
/// falling back to system defaults for unspecified settings.
module uln_302::oapp_uln_config;

use sui::bcs;
use uln_302::uln_config::{Self, UlnConfig};

// === Errors ===

const EInvalidConfirmations: u64 = 1;
const EInvalidRequiredDVNs: u64 = 2;
const EInvalidOptionalDVNs: u64 = 3;

// === Structs ===

/// Configuration struct for OApp-specific ULN settings.
public struct OAppUlnConfig has copy, drop, store {
    // Whether to use default confirmations
    use_default_confirmations: bool,
    // Whether to use default required DVNs
    use_default_required_dvns: bool,
    // Whether to use default optional DVNs
    use_default_optional_dvns: bool,
    // OApp-specific ULN configuration (used when defaults are not applied)
    uln_config: UlnConfig,
}

// === Creation ===

/// Creates a new OAppUlnConfig with all defaults enabled.
public fun new(): OAppUlnConfig {
    OAppUlnConfig {
        use_default_confirmations: true,
        use_default_required_dvns: true,
        use_default_optional_dvns: true,
        uln_config: uln_config::new(),
    }
}

/// Creates a new OAppUlnConfig with the specified parameters.
public fun create(
    use_default_confirmations: bool,
    use_default_required_dvns: bool,
    use_default_optional_dvns: bool,
    uln_config: UlnConfig,
): OAppUlnConfig {
    OAppUlnConfig { use_default_confirmations, use_default_required_dvns, use_default_optional_dvns, uln_config }
}

// === Getters ===

/// Returns whether this config uses default confirmations.
public fun use_default_confirmations(config: &OAppUlnConfig): bool {
    config.use_default_confirmations
}

/// Returns whether this config uses default required DVNs.
public fun use_default_required_dvns(config: &OAppUlnConfig): bool {
    config.use_default_required_dvns
}

/// Returns whether this config uses default optional DVNs.
public fun use_default_optional_dvns(config: &OAppUlnConfig): bool {
    config.use_default_optional_dvns
}

/// Returns a reference to the underlying ULN configuration.
public fun uln_config(config: &OAppUlnConfig): &UlnConfig {
    &config.uln_config
}

// === Deserialization ===

/// Deserializes an OAppUlnConfig from BCS-encoded bytes.
///
/// The expected byte format is:
/// 1. use_default_confirmations (bool) - 1 byte
/// 2. use_default_required_dvns (bool) - 1 byte
/// 3. use_default_optional_dvns (bool) - 1 byte
/// 4. uln_config (UlnConfig) - variable length
public fun deserialize(bytes: vector<u8>): OAppUlnConfig {
    let mut bcs = bcs::new(bytes);
    let use_default_confirmations = bcs.peel_bool();
    let use_default_required_dvns = bcs.peel_bool();
    let use_default_optional_dvns = bcs.peel_bool();
    let uln_config = uln_config::deserialize(bcs.into_remainder_bytes());
    OAppUlnConfig { use_default_confirmations, use_default_required_dvns, use_default_optional_dvns, uln_config }
}

// === Validation Functions ===

/// Validates an OAppUlnConfig for correctness.
///
/// Checks:
/// - When using defaults, corresponding config values must be empty/zero
/// - When not using defaults, the provided values must be valid
public fun assert_oapp_config(config: &OAppUlnConfig) {
    if (config.use_default_confirmations) {
        assert!(config.uln_config().confirmations() == 0, EInvalidConfirmations);
    };

    if (config.use_default_required_dvns) {
        assert!(config.uln_config().required_dvns().is_empty(), EInvalidRequiredDVNs);
    } else {
        config.uln_config().assert_required_dvns();
    };

    if (config.use_default_optional_dvns) {
        assert!(
            config.uln_config().optional_dvn_threshold() == 0 && config.uln_config().optional_dvns().is_empty(),
            EInvalidOptionalDVNs,
        );
    } else {
        config.uln_config().assert_optional_dvns();
    }
}

/// Merges OApp config with default config to get effective configuration.
///
/// For each setting type (confirmations, required DVNs, optional DVNs):
/// - If use_default flag is true, uses the default config value
/// - Otherwise, uses the OApp config value
///
/// Ensures the final configuration has at least one DVN for verification.
public fun get_effective_config(oapp_config: &OAppUlnConfig, default_config: &UlnConfig): UlnConfig {
    let confirmations = if (oapp_config.use_default_confirmations) {
        default_config.confirmations()
    } else {
        oapp_config.uln_config().confirmations()
    };

    let required_dvns = if (oapp_config.use_default_required_dvns) {
        *default_config.required_dvns()
    } else {
        *oapp_config.uln_config().required_dvns()
    };

    let (optional_dvns, optional_dvn_threshold) = if (oapp_config.use_default_optional_dvns) {
        (*default_config.optional_dvns(), default_config.optional_dvn_threshold())
    } else {
        (*oapp_config.uln_config().optional_dvns(), oapp_config.uln_config().optional_dvn_threshold())
    };

    // create the final uln config and ensure there is at least one dvn
    let uln_config = uln_config::create(confirmations, required_dvns, optional_dvns, optional_dvn_threshold);
    uln_config.assert_at_least_one_dvn();

    uln_config
}
