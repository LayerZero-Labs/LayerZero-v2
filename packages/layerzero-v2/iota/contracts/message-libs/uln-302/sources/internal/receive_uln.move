/// Receive ULN (Ultra Light Node) Module
///
/// This module implements the receiving functionality for the ULN 302 message library
/// in the LayerZero V2 protocol. It manages DVN configurations and verification of
/// inbound messages through multiple DVNs.
module uln_302::receive_uln;

use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use iota::{event, table::{Self, Table}};
use uln_302::{oapp_uln_config::{Self, OAppUlnConfig}, uln_config::UlnConfig};
use utils::{bytes32::Bytes32, hash, table_ext};

// === Errors ===

const EConfirmationsNotFound: u64 = 1;
const EDefaultUlnConfigNotFound: u64 = 2;
const EInvalidEid: u64 = 3;
const EOAppUlnConfigNotFound: u64 = 4;
const EVerifying: u64 = 5;

// === Structs ===

/// Main storage struct for the Receive ULN functionality.
/// Manages both default configurations (per source) and OApp-specific overrides
/// for DVN verification settings used in cross-chain message receiving.
public struct ReceiveUln has store {
    // Default ULN configurations indexed by source endpoint ID
    default_uln_configs: Table<u32, UlnConfig>,
    // OApp-specific ULN configurations indexed by (receiver, src_eid)
    oapp_uln_configs: Table<OAppConfigKey, OAppUlnConfig>,
    // Address of the shared Verification object
    verification: address,
}

/// Composite key used to identify OApp-specific configurations.
public struct OAppConfigKey has copy, drop, store {
    receiver: address,
    src_eid: u32,
}

/// Shared object that stores DVN confirmations for message verification.
/// Each message requires confirmations from multiple DVNs based on the ULN configuration.
public struct Verification has key {
    id: UID,
    // Maps confirmation keys to the number of confirmations
    confirmations: Table<ConfirmationKey, u64>,
}

/// Key used to identify a specific DVN confirmation for a message.
public struct ConfirmationKey has copy, drop, store {
    header_hash: Bytes32,
    payload_hash: Bytes32,
    dvn: address,
}

// === Events ===

public struct PayloadVerifiedEvent has copy, drop {
    dvn: address,
    header: vector<u8>,
    confirmations: u64,
    proof_hash: Bytes32,
}

public struct DefaultUlnConfigSetEvent has copy, drop {
    src_eid: u32,
    config: UlnConfig,
}

public struct UlnConfigSetEvent has copy, drop {
    receiver: address,
    src_eid: u32,
    config: OAppUlnConfig,
}

// === Initialization ===

/// Creates a new ReceiveUln with empty configuration tables and a shared Verification object.
/// This is typically called during the ULN302 initialization.
public(package) fun new_receive_uln(ctx: &mut TxContext): ReceiveUln {
    // Create shared verification object for storing DVN confirmations
    let verification = Verification {
        id: object::new(ctx),
        confirmations: table::new(ctx),
    };
    let id = object::id_address(&verification);
    transfer::share_object(verification);

    ReceiveUln {
        default_uln_configs: table::new(ctx),
        oapp_uln_configs: table::new(ctx),
        verification: id,
    }
}

// === Configuration Functions ===

/// Sets the default ULN configuration for a source endpoint.
/// This configuration defines the DVN requirements and verification settings
/// that will be used as fallback for all OApps receiving from this source.
public(package) fun set_default_uln_config(self: &mut ReceiveUln, src_eid: u32, new_config: UlnConfig) {
    // Validate that this is a proper default configuration
    new_config.assert_default_config();
    table_ext::upsert!(&mut self.default_uln_configs, src_eid, new_config);
    event::emit(DefaultUlnConfigSetEvent { src_eid, config: new_config });
}

/// Sets an OApp-specific ULN configuration for a source endpoint.
/// This configuration can override the default DVN requirements for the specific OApp.
/// The configuration is validated by getting the effective configuration.
public(package) fun set_uln_config(self: &mut ReceiveUln, receiver: address, src_eid: u32, new_config: OAppUlnConfig) {
    // Validate the OApp-specific configuration
    new_config.assert_oapp_config();
    // Ensure there is at least one DVN in the effective config by getting it
    new_config.get_effective_config(self.get_default_uln_config(src_eid));
    table_ext::upsert!(&mut self.oapp_uln_configs, OAppConfigKey { receiver, src_eid }, new_config);
    event::emit(UlnConfigSetEvent { receiver, src_eid, config: new_config });
}

// === Verification Functions ===

/// Records a DVN's verification for a specific message.
/// Stores the confirmation for the given packet header and payload combination.
public(package) fun verify(
    self: &mut Verification,
    dvn: address,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    confirmations: u64,
) {
    // Store the confirmation for this DVN and message combination
    table_ext::upsert!(
        &mut self.confirmations,
        ConfirmationKey { header_hash: hash::keccak256!(&packet_header), payload_hash, dvn },
        confirmations,
    );
    event::emit(PayloadVerifiedEvent { dvn, header: packet_header, confirmations, proof_hash: payload_hash });
}

/// Verifies a message has sufficient DVN confirmations and cleans up storage.
/// Returns the decoded packet header after successful verification.
public(package) fun verify_and_reclaim_storage(
    self: &ReceiveUln,
    verification: &mut Verification,
    local_eid: u32,
    encoded_packet_header: vector<u8>,
    payload_hash: Bytes32,
): PacketHeader {
    // Decode header and validate endpoint ID
    let header = packet_v1_codec::decode_header(encoded_packet_header);
    assert!(header.dst_eid() == local_eid, EInvalidEid);
    let header_hash = hash::keccak256!(&encoded_packet_header);

    // Get effective configuration for verification
    let uln_config = self.get_effective_uln_config(header.receiver().to_address(), header.src_eid());

    // Verify confirmations, including both required and optional DVNs
    assert!(verification.verifiable_internal(&uln_config, header_hash, payload_hash), EVerifying);

    // Clean up required DVN confirmations (guaranteed to exist)
    uln_config.required_dvns().do_ref!(|dvn| {
        verification.confirmations.remove(ConfirmationKey { header_hash, payload_hash, dvn: *dvn });
    });

    // Clean up optional DVN confirmations (if they exist)
    uln_config.optional_dvns().do_ref!(|dvn| {
        table_ext::try_remove!(
            &mut verification.confirmations,
            ConfirmationKey { header_hash, payload_hash, dvn: *dvn },
        );
    });

    header
}

// === Configuration View Functions ===

/// Gets the default ULN configuration for a source endpoint.
/// Returns a reference to avoid copying the config data.
/// Reverts if no default configuration has been set for this source.
public(package) fun get_default_uln_config(self: &ReceiveUln, src_eid: u32): &UlnConfig {
    table_ext::borrow_or_abort!(&self.default_uln_configs, src_eid, EDefaultUlnConfigNotFound)
}

/// Gets the OApp-specific ULN configuration for a source endpoint.
/// Returns a reference to avoid copying the config data.
/// Reverts if no OApp-specific configuration has been set for this receiver and source.
public(package) fun get_oapp_uln_config(self: &ReceiveUln, receiver: address, src_eid: u32): &OAppUlnConfig {
    table_ext::borrow_or_abort!(&self.oapp_uln_configs, OAppConfigKey { receiver, src_eid }, EOAppUlnConfigNotFound)
}

/// Gets the effective ULN configuration by merging OApp-specific config with default.
/// If no OApp-specific config exists, uses an empty config that will inherit all defaults.
/// The default config is required and this function will revert if it doesn't exist.
/// Returns the merged configuration that defines DVN requirements for the message.
public(package) fun get_effective_uln_config(self: &ReceiveUln, receiver: address, src_eid: u32): UlnConfig {
    // Default config is required for all sources
    let default_uln_config = self.get_default_uln_config(src_eid);
    // OApp-specific config is optional - use empty config if none exists
    let oapp_uln_config = table_ext::borrow_with_default!(
        &self.oapp_uln_configs,
        OAppConfigKey { src_eid, receiver },
        &oapp_uln_config::new(),
    );
    // Merge OApp config with default to get effective configuration
    oapp_uln_config.get_effective_config(default_uln_config)
}

/// Checks if a source endpoint is supported by this ReceiveUln instance.
/// An endpoint is supported if a default ULN configuration exists for it.
public(package) fun is_supported_eid(self: &ReceiveUln, src_eid: u32): bool {
    self.default_uln_configs.contains(src_eid)
}

// === Verification View Functions ===

/// Checks if a message can be verified based on current DVN confirmations.
/// Returns true if the message has received sufficient confirmations from required DVNs
/// and optional DVNs (if threshold > 0) based on the effective ULN configuration.
public(package) fun verifiable(
    self: &ReceiveUln,
    verification: &Verification,
    local_eid: u32,
    encoded_packet_header: vector<u8>,
    payload_hash: Bytes32,
): bool {
    // Decode header and validate endpoint ID
    let header = packet_v1_codec::decode_header(encoded_packet_header);
    assert!(header.dst_eid() == local_eid, EInvalidEid);

    // Get effective config and check verification status
    let uln_config = self.get_effective_uln_config(header.receiver().to_address(), header.src_eid());
    verification.verifiable_internal(&uln_config, hash::keccak256!(&encoded_packet_header), payload_hash)
}

/// Gets the number of confirmations recorded by a specific DVN for a message.
/// Reverts if no confirmations have been recorded for this combination.
public(package) fun get_confirmations(
    self: &Verification,
    dvn: address,
    header_hash: Bytes32,
    payload_hash: Bytes32,
): u64 {
    let key = ConfirmationKey { dvn, header_hash, payload_hash };
    *table_ext::borrow_or_abort!(&self.confirmations, key, EConfirmationsNotFound)
}

/// Returns the address of the shared Verification object.
public(package) fun get_verification(self: &ReceiveUln): address {
    self.verification
}

// === Internal Functions ===

/// Checks if a message has sufficient DVN confirmations based on the ULN configuration.
/// Validates that all required DVNs have provided confirmations and that the optional
/// DVN threshold is met (if applicable).
fun verifiable_internal(self: &Verification, config: &UlnConfig, header_hash: Bytes32, payload_hash: Bytes32): bool {
    let required_dvns = config.required_dvns();
    let optional_dvns = config.optional_dvns();
    let optional_dvn_threshold = config.optional_dvn_threshold() as u64;
    let confirmations = config.confirmations();

    // Check all required DVNs have sufficient confirmations
    if (required_dvns.length() > 0) {
        if (!required_dvns.all!(|dvn| self.verified(*dvn, header_hash, payload_hash, confirmations))) return false;

        // If no optional DVN threshold, return true
        if (optional_dvn_threshold == 0) return true;
    };

    // Count verified optional DVNs and check against threshold
    let mut i = 0;
    let mut verified_optional_dvn_count = 0;
    while (i < optional_dvns.length()) {
        if (self.verified(optional_dvns[i], header_hash, payload_hash, confirmations)) {
            verified_optional_dvn_count = verified_optional_dvn_count + 1;
            if (verified_optional_dvn_count >= optional_dvn_threshold) return true;
        };
        i = i + 1;
    };

    false
}

/// Checks if a specific DVN has provided sufficient confirmations for a message.
fun verified(
    self: &Verification,
    dvn: address,
    header_hash: Bytes32,
    payload_hash: Bytes32,
    required_confirmations: u64,
): bool {
    let key = ConfirmationKey { header_hash, payload_hash, dvn };
    if (self.confirmations.contains(key)) {
        self.confirmations[key] >= required_confirmations
    } else {
        false
    }
}

// === Test-only Functions ===

#[test_only]
public(package) fun verifiable_internal_for_test(
    verification: &Verification,
    config: &UlnConfig,
    header_hash: Bytes32,
    payload_hash: Bytes32,
): bool {
    verification.verifiable_internal(config, header_hash, payload_hash)
}

#[test_only]
public(package) fun verified_for_test(
    verification: &Verification,
    dvn: address,
    header_hash: Bytes32,
    payload_hash: Bytes32,
    required_confirmations: u64,
): bool {
    verification.verified(dvn, header_hash, payload_hash, required_confirmations)
}

#[test_only]
public(package) fun create_verification_for_testing(ctx: &mut TxContext): Verification {
    Verification {
        id: object::new(ctx),
        confirmations: table::new(ctx),
    }
}

#[test_only]
public(package) fun create_payload_verified_event(
    dvn: address,
    header: vector<u8>,
    confirmations: u64,
    proof_hash: Bytes32,
): PayloadVerifiedEvent {
    PayloadVerifiedEvent { dvn, header, confirmations, proof_hash }
}

#[test_only]
public(package) fun create_default_uln_config_set_event(src_eid: u32, config: UlnConfig): DefaultUlnConfigSetEvent {
    DefaultUlnConfigSetEvent { src_eid, config }
}

#[test_only]
public(package) fun create_uln_config_set_event(
    receiver: address,
    src_eid: u32,
    config: OAppUlnConfig,
): UlnConfigSetEvent {
    UlnConfigSetEvent { receiver, src_eid, config }
}

// === Test Only Functions ===

#[test_only]
public fun create_test_verification(ctx: &mut TxContext): Verification {
    Verification {
        id: object::new(ctx),
        confirmations: table::new(ctx),
    }
}

#[test_only]
public fun destroy_test_verification(verification: Verification) {
    let Verification { id, confirmations } = verification;
    confirmations.drop();
    id.delete();
}

#[test_only]
public fun test_is_verified(verification: &Verification): bool {
    !verification.confirmations.is_empty()
}
