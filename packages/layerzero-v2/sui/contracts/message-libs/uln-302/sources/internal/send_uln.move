/// Send ULN (Ultra Light Node) Module
///
/// This module implements the sending functionality for the ULN 302 message library
/// in the LayerZero V2 protocol. It manages configurations for DVNs and executors,
/// handles fee calculations, and orchestrates the message sending process.
module uln_302::send_uln;

use endpoint_v2::{
    message_lib_quote::QuoteParam,
    message_lib_send::{Self, SendParam, SendResult},
    messaging_fee::{Self, MessagingFee},
    utils
};
use message_lib_common::{fee_recipient::FeeRecipient, packet_v1_codec, worker_options::{Self, DVNOptions}};
use sui::{coin::Coin, event, sui::SUI, table::{Self, Table}};
use treasury::treasury::Treasury;
use uln_302::{executor_config::{Self, ExecutorConfig}, oapp_uln_config::{Self, OAppUlnConfig}, uln_config::UlnConfig};
use uln_common::{
    dvn_assign_job::{Self, AssignJobParam as DvnAssignJobParam},
    dvn_get_fee::{Self, GetFeeParam as DvnGetFeeParam},
    executor_assign_job::{Self, AssignJobParam as ExecutorAssignJobParam},
    executor_get_fee::{Self, GetFeeParam as ExecutorGetFeeParam}
};
use utils::{bytes32::Bytes32, table_ext};
use zro::zro::ZRO;

// === Errors ===

const EDefaultExecutorConfigNotFound: u64 = 1;
const EDefaultUlnConfigNotFound: u64 = 2;
const EInvalidMessageSize: u64 = 3;
const EOAppExecutorConfigNotFound: u64 = 4;
const EOAppUlnConfigNotFound: u64 = 5;

// === Structs ===

/// Main storage struct for the Send ULN functionality.
/// Manages both default configurations (per destination) and OApp-specific overrides
/// for DVN and executor settings used in cross-chain message sending.
public struct SendUln has store {
    // Default executor configurations indexed by destination endpoint ID
    default_executor_configs: Table<u32, ExecutorConfig>,
    // Default ULN configurations indexed by destination endpoint ID
    default_uln_configs: Table<u32, UlnConfig>,
    // OApp-specific executor configurations indexed by (sender, dst_eid)
    oapp_executor_configs: Table<OAppConfigKey, ExecutorConfig>,
    // OApp-specific ULN configurations indexed by (sender, dst_eid)
    oapp_uln_configs: Table<OAppConfigKey, OAppUlnConfig>,
}

/// Composite key used to identify OApp-specific configurations.
public struct OAppConfigKey has copy, drop, store {
    sender: address,
    dst_eid: u32,
}

// === Events ===

public struct ExecutorFeePaidEvent has copy, drop {
    guid: Bytes32,
    executor: address,
    fee: FeeRecipient,
}

public struct DVNFeePaidEvent has copy, drop {
    guid: Bytes32,
    dvns: vector<address>,
    fees: vector<FeeRecipient>,
}

public struct DefaultExecutorConfigSetEvent has copy, drop {
    dst_eid: u32,
    config: ExecutorConfig,
}

public struct ExecutorConfigSetEvent has copy, drop {
    sender: address,
    dst_eid: u32,
    config: ExecutorConfig,
}

public struct DefaultUlnConfigSetEvent has copy, drop {
    dst_eid: u32,
    config: UlnConfig,
}

public struct UlnConfigSetEvent has copy, drop {
    sender: address,
    dst_eid: u32,
    config: OAppUlnConfig,
}

// === Initialization ===

/// Creates a new SendUln with empty configuration tables.
/// This is typically called during the ULN302 initialization.
public(package) fun new_send_uln(ctx: &mut TxContext): SendUln {
    SendUln {
        default_executor_configs: table::new(ctx),
        default_uln_configs: table::new(ctx),
        oapp_executor_configs: table::new(ctx),
        oapp_uln_configs: table::new(ctx),
    }
}

// === Executor Configuration Functions ===

/// Sets the default executor configuration for a destination endpoint.
/// This configuration will be used as a fallback for all OApps that don't have
/// a specific executor configuration set for this destination.
public(package) fun set_default_executor_config(self: &mut SendUln, dst_eid: u32, new_config: ExecutorConfig) {
    // Validate that this is a proper default configuration
    new_config.assert_default_config();
    table_ext::upsert!(&mut self.default_executor_configs, dst_eid, new_config);
    event::emit(DefaultExecutorConfigSetEvent { dst_eid, config: new_config });
}

/// Sets an OApp-specific executor configuration for a destination endpoint.
/// This configuration will override the default executor config for the specific
/// OApp when sending messages to the given destination.
public(package) fun set_executor_config(self: &mut SendUln, sender: address, dst_eid: u32, new_config: ExecutorConfig) {
    table_ext::upsert!(&mut self.oapp_executor_configs, OAppConfigKey { sender, dst_eid }, new_config);
    event::emit(ExecutorConfigSetEvent { sender, dst_eid, config: new_config });
}

// === ULN Configuration Functions ===

/// Sets the default ULN configuration for a destination endpoint.
/// This configuration defines the DVN requirements and verification settings
/// that will be used as fallback for all OApps sending to this destination.
public(package) fun set_default_uln_config(self: &mut SendUln, dst_eid: u32, new_config: UlnConfig) {
    // Validate that this is a proper default configuration
    new_config.assert_default_config();
    table_ext::upsert!(&mut self.default_uln_configs, dst_eid, new_config);
    event::emit(DefaultUlnConfigSetEvent { dst_eid, config: new_config });
}

/// Sets an OApp-specific ULN configuration for a destination endpoint.
/// This configuration can override the default DVN requirements for the specific OApp.
/// The configuration is validated by getting the effective configuration.
public(package) fun set_uln_config(self: &mut SendUln, sender: address, dst_eid: u32, new_config: OAppUlnConfig) {
    // Validate the OApp-specific configuration
    new_config.assert_oapp_config();
    // Ensure there is at least one DVN in the effective config by getting it
    new_config.get_effective_config(self.get_default_uln_config(dst_eid));
    table_ext::upsert!(&mut self.oapp_uln_configs, OAppConfigKey { sender, dst_eid }, new_config);
    event::emit(UlnConfigSetEvent { sender, dst_eid, config: new_config });
}

// === Message Processing Functions ===

/// Prepares fee quote parameters for a message by gathering all required worker information.
/// Returns the executor address and parameters, plus lists of DVN addresses and parameters
/// needed to calculate the total cost for sending the message.
public(package) fun quote(
    self: &SendUln,
    param: &QuoteParam,
): (address, ExecutorGetFeeParam, vector<address>, vector<DvnGetFeeParam>) {
    let sender = param.packet().sender();
    let dst_eid = param.packet().dst_eid();
    let packet_header = packet_v1_codec::encode_packet_header(param.packet());
    let payload_hash = packet_v1_codec::payload_hash(param.packet());

    // Split worker options into executor and DVN-specific options
    let (executor_options, dvn_options) = worker_options::split_worker_options(param.options());

    // Get the effective executor config
    let executor_config = self.get_effective_executor_config(sender, dst_eid);
    // Assert the message size is within the executor's max message size and create executor parameters
    let message_length = param.packet().message_length();
    assert!(message_length <= executor_config.max_message_size(), EInvalidMessageSize);
    let executor_param = executor_get_fee::create_param(dst_eid, sender, message_length, executor_options);

    // Get the effective ULN config and create DVN parameters
    let uln_config = self.get_effective_uln_config(sender, dst_eid);
    let (dvns, dvn_params) = create_dvn_params(&uln_config, sender, dst_eid, packet_header, payload_hash, &dvn_options);

    (executor_config.executor(), executor_param, dvns, dvn_params)
}

/// Confirms the quote by calculating the total messaging fee including treasury fees.
/// Takes the executor and DVN fees received from quote calls, adds treasury fees,
/// and returns a complete MessagingFee structure for the message.
public(package) fun confirm_quote(
    param: &QuoteParam,
    executor_fee: u64,
    dvn_fees: vector<u64>,
    treasury: &Treasury,
): MessagingFee {
    // Calculate total worker fees (executor + all DVNs)
    let total_worker_fee = dvn_fees.fold!(executor_fee, |total, dvn_fee| total + dvn_fee);
    // Get treasury fees based on total worker fees and payment method
    let (treasury_native_fee, treasury_zro_fee) = treasury.get_fee(total_worker_fee, param.pay_in_zro());
    // Create final messaging fee including all components
    messaging_fee::create(total_worker_fee + treasury_native_fee, treasury_zro_fee)
}

/// Prepares job assignment parameters for sending a message.
/// Converts quote parameters into actual job assignment parameters that will be
/// sent to the executor and DVNs to process the message.
public(package) fun send(
    self: &SendUln,
    param: &SendParam,
): (address, ExecutorAssignJobParam, vector<address>, vector<DvnAssignJobParam>) {
    // Get quote parameters for all workers
    let (executor, executor_qt_param, dvns, dvn_qt_params) = self.quote(param.base());
    // Convert DVN quote parameters to job assignment parameters
    let dvn_params = dvn_qt_params.map!(|param| dvn_assign_job::create_param(param));
    // Convert executor quote parameter to job assignment parameter
    let executor_param = executor_assign_job::create_param(executor_qt_param);
    (executor, executor_param, dvns, dvn_params)
}

/// Confirms the send operation after workers have processed the message.
/// Calculates final fees including treasury charges, emits payment events,
/// and creates the SendResult for the message library.
public(package) fun confirm_send(
    param: &SendParam,
    executor: address,
    executor_recipient: FeeRecipient,
    dvns: vector<address>,
    dvn_recipients: vector<FeeRecipient>,
    treasury: &Treasury,
): SendResult {
    // Calculate total worker fees from executor and all DVNs
    let mut total_worker_fee = executor_recipient.fee();
    total_worker_fee = dvn_recipients.fold!(total_worker_fee, |total, dvn_recipient| total + dvn_recipient.fee());

    // Get treasury fees based on total worker fees and payment method
    let (treasury_native_fee, treasury_zro_fee) = treasury.get_fee(total_worker_fee, param.base().pay_in_zro());

    // Emit fee payment events
    let guid = param.base().packet().guid();
    event::emit(ExecutorFeePaidEvent { guid, executor, fee: executor_recipient });
    event::emit(DVNFeePaidEvent { guid, dvns, fees: dvn_recipients });

    // Create the final send result with encoded packet and total fees
    message_lib_send::create_result(
        packet_v1_codec::encode_packet(param.base().packet()),
        messaging_fee::create(total_worker_fee + treasury_native_fee, treasury_zro_fee),
    )
}

/// Handles the distribution of collected fees to all service providers.
/// Splits the provided coins to pay the executor, DVNs.
/// Any remaining native tokens and all ZRO tokens are transferred to the treasury.
public(package) fun handle_fees(
    treasury: &Treasury,
    executor_recipient: FeeRecipient,
    dvn_recipients: vector<FeeRecipient>,
    mut native_token: Coin<SUI>,
    zro_token: Coin<ZRO>,
    ctx: &mut TxContext,
) {
    // Pay the executor their fee
    let executor_fee = native_token.split(executor_recipient.fee(), ctx);
    utils::transfer_coin(executor_fee, executor_recipient.recipient());

    // Pay each DVN their respective fee
    dvn_recipients.do_ref!(|dvn_recipient| {
        let dvn_fee = native_token.split(dvn_recipient.fee(), ctx);
        utils::transfer_coin(dvn_fee, dvn_recipient.recipient());
    });

    // Transfer remaining native tokens (treasury fee) and all ZRO tokens to treasury
    let treasury_recipient = treasury.fee_recipient();
    utils::transfer_coin(native_token, treasury_recipient); // Remaining = treasury native fee
    utils::transfer_coin(zro_token, treasury_recipient); // All ZRO goes to treasury
}

// === Configuration View Functions ===

/// Gets the default executor configuration for a destination endpoint.
/// Reverts if no default configuration has been set for this destination.
public(package) fun get_default_executor_config(self: &SendUln, dst_eid: u32): &ExecutorConfig {
    table_ext::borrow_or_abort!(&self.default_executor_configs, dst_eid, EDefaultExecutorConfigNotFound)
}

/// Gets the OApp-specific executor configuration for a destination endpoint.
/// Reverts if no OApp-specific configuration has been set for this sender and destination.
public(package) fun get_oapp_executor_config(self: &SendUln, sender: address, dst_eid: u32): &ExecutorConfig {
    table_ext::borrow_or_abort!(
        &self.oapp_executor_configs,
        OAppConfigKey { sender, dst_eid },
        EOAppExecutorConfigNotFound,
    )
}

/// Gets the effective executor configuration by merging OApp-specific config with default.
/// If no OApp-specific config exists, uses an empty config that will inherit all defaults.
/// The default config is required and this function will revert if it doesn't exist.
public(package) fun get_effective_executor_config(self: &SendUln, sender: address, dst_eid: u32): ExecutorConfig {
    // Default config is required for all destinations
    let default_config = self.get_default_executor_config(dst_eid);
    // OApp-specific config is optional - use empty config if none exists
    let custom_config = table_ext::borrow_with_default!(
        &self.oapp_executor_configs,
        OAppConfigKey { sender, dst_eid },
        &executor_config::new(),
    );
    // Merge custom config with default to get effective configuration
    custom_config.get_effective_executor_config(default_config)
}

/// Gets the default ULN configuration for a destination endpoint.
/// Returns a reference to avoid copying the config data.
/// Reverts if no default configuration has been set for this destination.
public(package) fun get_default_uln_config(self: &SendUln, dst_eid: u32): &UlnConfig {
    table_ext::borrow_or_abort!(&self.default_uln_configs, dst_eid, EDefaultUlnConfigNotFound)
}

/// Gets the OApp-specific ULN configuration for a destination endpoint.
/// Returns a reference to avoid copying the config data.
/// Reverts if no OApp-specific configuration has been set for this sender and destination.
public(package) fun get_oapp_uln_config(self: &SendUln, sender: address, dst_eid: u32): &OAppUlnConfig {
    table_ext::borrow_or_abort!(&self.oapp_uln_configs, OAppConfigKey { sender, dst_eid }, EOAppUlnConfigNotFound)
}

/// Gets the effective ULN configuration by merging OApp-specific config with default.
/// If no OApp-specific config exists, uses an empty config that will inherit all defaults.
/// The default config is required and this function will revert if it doesn't exist.
/// Returns the merged configuration that defines DVN requirements for the message.
public(package) fun get_effective_uln_config(self: &SendUln, sender: address, dst_eid: u32): UlnConfig {
    // Default config is required for all destinations
    let default_uln_config = self.get_default_uln_config(dst_eid);
    // OApp-specific config is optional - use empty config if none exists
    let oapp_uln_config = table_ext::borrow_with_default!(
        &self.oapp_uln_configs,
        OAppConfigKey { sender, dst_eid },
        &oapp_uln_config::new(),
    );
    // Merge OApp config with default to get effective configuration
    oapp_uln_config.get_effective_config(default_uln_config)
}

/// Checks if a destination endpoint is supported by this SendUln instance.
/// An endpoint is supported if both default ULN and executor configurations exist.
/// Returns true if the destination is supported, false otherwise.
public(package) fun is_supported_eid(self: &SendUln, dst_eid: u32): bool {
    self.default_uln_configs.contains(dst_eid) && self.default_executor_configs.contains(dst_eid)
}

// === Internal Functions ===

/// Creates DVN parameters for fee calculation and job assignment.
/// Combines required and optional DVNs from the ULN config, matches them with
/// their corresponding options, and creates fee parameters for each DVN.
/// Returns both the list of DVN addresses and their corresponding fee parameters.
fun create_dvn_params(
    uln_config: &UlnConfig,
    sender: address,
    dst_eid: u32,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    dvn_options: &vector<DVNOptions>,
): (vector<address>, vector<DvnGetFeeParam>) {
    // Combine required and optional DVNs into a single list
    let mut dvns = *uln_config.required_dvns();
    dvns.append(*uln_config.optional_dvns());

    // Create fee parameters for each DVN, matching with their specific options
    let mut i = 0;
    let dvn_params = dvns.map_ref!(|_| {
        // Get the options specific to this DVN
        // If no options are found, the options vector will be empty
        let options = worker_options::get_matching_options(dvn_options, i);
        i = i + 1;
        // Create the fee parameter for this DVN
        dvn_get_fee::create_param(dst_eid, packet_header, payload_hash, uln_config.confirmations(), sender, options)
    });
    (dvns, dvn_params)
}

// === Test-Only Functions ===

#[test_only]
public(package) fun create_executor_fee_paid_event(guid: Bytes32, executor: address, fee: u64): ExecutorFeePaidEvent {
    use message_lib_common::fee_recipient;
    ExecutorFeePaidEvent { guid, executor, fee: fee_recipient::create(fee, executor) }
}

#[test_only]
public(package) fun create_dvn_fee_paid_event(
    guid: Bytes32,
    dvns: vector<address>,
    fees: vector<u64>,
): DVNFeePaidEvent {
    use message_lib_common::fee_recipient;
    let mut fee_recipients = vector[];
    let mut i = 0;
    while (i < vector::length(&dvns)) {
        let dvn = vector::borrow(&dvns, i);
        let fee = vector::borrow(&fees, i);
        vector::push_back(&mut fee_recipients, fee_recipient::create(*fee, *dvn));
        i = i + 1;
    };
    DVNFeePaidEvent { guid, dvns, fees: fee_recipients }
}

#[test_only]
public(package) fun create_default_executor_config_set_event(
    dst_eid: u32,
    config: ExecutorConfig,
): DefaultExecutorConfigSetEvent {
    DefaultExecutorConfigSetEvent { dst_eid, config }
}

#[test_only]
public(package) fun create_executor_config_set_event(
    sender: address,
    dst_eid: u32,
    config: ExecutorConfig,
): ExecutorConfigSetEvent {
    ExecutorConfigSetEvent { sender, dst_eid, config }
}

#[test_only]
public(package) fun create_default_uln_config_set_event(dst_eid: u32, config: UlnConfig): DefaultUlnConfigSetEvent {
    DefaultUlnConfigSetEvent { dst_eid, config }
}

#[test_only]
public(package) fun create_uln_config_set_event(
    sender: address,
    dst_eid: u32,
    config: OAppUlnConfig,
): UlnConfigSetEvent {
    UlnConfigSetEvent { sender, dst_eid, config }
}
