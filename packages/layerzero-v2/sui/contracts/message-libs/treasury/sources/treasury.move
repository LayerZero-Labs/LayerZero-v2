/// Treasury Module
///
/// This module manages LayerZero protocol fees and treasury operations.
/// The treasury can collect fees in native tokens or ZRO tokens and provides
/// flexible fee configuration for the LayerZero protocol.
///
/// The treasury supports two types of fees:
/// - **Native Fee**: Percentage-based fee on native token amounts (configurable basis points)
/// - **ZRO Fee**: Fixed fee paid in ZRO tokens (alternative to native fees)
module treasury::treasury;

use sui::event;

// === Constants ===

/// Denominator for basis point calculations (10000 = 100%).
/// Used to calculate percentage-based native fees with precision.
const BPS_DENOMINATOR: u64 = 10000;

// === Errors ===

const EInvalidFeeRecipient: u64 = 1;
const EInvalidNativeFeeBp: u64 = 2;
const EZroNotEnabled: u64 = 3;

// === Structs ===

/// The main treasury object that manages fee collection and configuration.
///
/// This shared object stores all treasury settings and provides the interface
/// for fee calculation and administration. It supports both native token and
/// ZRO token fee collection with flexible configuration options.
public struct Treasury has key {
    /// Unique object identifier
    id: UID,
    /// Address that receives collected fees
    fee_recipient: address,
    /// Native fee in basis points (0-10000, where 10000 = 100%)
    native_fee_bp: u64,
    /// Fixed fee amount in ZRO tokens
    zro_fee: u64,
    /// Whether ZRO fee payment is currently enabled
    zro_enabled: bool,
    /// Global toggle for all fee collection
    fee_enabled: bool,
}

/// Administrative capability for treasury configuration.
///
/// This capability object allows its holder to modify treasury settings.
/// It should be held by authorized administrators only.
public struct AdminCap has key, store {
    id: UID,
}

// === Initialization ===

/// Initializes the treasury module during package publication.
///
/// Creates a new Treasury shared object with default settings (all fees disabled)
/// and transfers the AdminCap to the package publisher for initial configuration.
fun init(ctx: &mut TxContext) {
    let treasury = Treasury {
        id: object::new(ctx),
        fee_recipient: @0x0, // Must be set by admin before enabling fees
        native_fee_bp: 0, // No native fees initially
        zro_fee: 0, // No ZRO fees initially
        zro_enabled: false, // ZRO payments disabled initially
        fee_enabled: false, // All fee collection disabled initially
    };
    transfer::share_object(treasury);
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Events ===

public struct FeeRecipientSetEvent has copy, drop {
    fee_recipient: address,
}

public struct NativeFeeBpSetEvent has copy, drop {
    native_fee_bp: u64,
}

public struct ZroFeeSetEvent has copy, drop {
    zro_fee: u64,
}

public struct ZroEnabledSetEvent has copy, drop {
    zro_enabled: bool,
}

public struct FeeEnabledSetEvent has copy, drop {
    fee_enabled: bool,
}

// === Public API ===

/// Calculates the treasury fee based on the payment method and current configuration.
///
/// This is the main fee calculation function used by the LayerZero protocol.
/// It returns different fee amounts based on whether the user chooses to pay
/// in native tokens or ZRO tokens.
///
/// Fee Calculation Logic:
/// - If fees are disabled globally: returns (0, 0)
/// - If paying in ZRO: returns (0, zro_fee) - requires ZRO to be enabled
/// - If paying in native: returns (percentage_of_total, 0) - based on basis points
public fun get_fee(self: &Treasury, total_native_fee: u64, pay_in_zro: bool): (u64, u64) {
    if (self.fee_enabled) {
        if (pay_in_zro) {
            assert!(self.zro_enabled, EZroNotEnabled);
            (0, self.zro_fee)
        } else {
            (total_native_fee * self.native_fee_bp / BPS_DENOMINATOR, 0)
        }
    } else {
        (0, 0)
    }
}

// === Admin Configuration Functions ===

/// Sets the address that will receive collected fees.
///
/// The fee recipient must be a valid address (cannot be @0x0). All treasury
/// fees will be transferred to this address when collected.
public fun set_fee_recipient(self: &mut Treasury, _admin: &AdminCap, fee_recipient: address) {
    assert!(fee_recipient != @0x0, EInvalidFeeRecipient);
    self.fee_recipient = fee_recipient;
    event::emit(FeeRecipientSetEvent { fee_recipient });
}

/// Sets the native fee rate in basis points.
public fun set_native_fee_bp(self: &mut Treasury, _admin: &AdminCap, native_fee_bp: u64) {
    assert!(native_fee_bp <= BPS_DENOMINATOR, EInvalidNativeFeeBp);
    self.native_fee_bp = native_fee_bp;
    event::emit(NativeFeeBpSetEvent { native_fee_bp });
}

/// Sets the fixed fee amount for ZRO token payments.
public fun set_zro_fee(self: &mut Treasury, _admin: &AdminCap, zro_fee: u64) {
    self.zro_fee = zro_fee;
    event::emit(ZroFeeSetEvent { zro_fee });
}

/// Enables or disables ZRO token fee payments.
///
/// When disabled, users cannot choose to pay fees in ZRO tokens and
/// must pay in native tokens according to the configured rate.
public fun set_zro_enabled(self: &mut Treasury, _admin: &AdminCap, zro_enabled: bool) {
    assert!(self.fee_recipient != @0x0, EInvalidFeeRecipient);
    self.zro_enabled = zro_enabled;
    event::emit(ZroEnabledSetEvent { zro_enabled });
}

/// Enables or disables all fee collection globally.
///
/// When disabled, the treasury will return zero fees regardless of
/// other configuration settings. This is a master switch for all
/// fee collection functionality.
public fun set_fee_enabled(self: &mut Treasury, _admin: &AdminCap, fee_enabled: bool) {
    if (fee_enabled) assert!(self.fee_recipient != @0x0, EInvalidFeeRecipient);
    self.fee_enabled = fee_enabled;
    event::emit(FeeEnabledSetEvent { fee_enabled });
}

// === View Functions ===

/// Returns the current fee recipient address.
public fun fee_recipient(self: &Treasury): address {
    self.fee_recipient
}

/// Returns the current native fee rate in basis points.
public fun native_fee_bp(self: &Treasury): u64 {
    self.native_fee_bp
}

/// Returns the current ZRO fee amount.
public fun zro_fee(self: &Treasury): u64 {
    self.zro_fee
}

/// Returns whether ZRO fee payments are currently enabled.
public fun zro_enabled(self: &Treasury): bool {
    self.zro_enabled
}

/// Returns whether fee collection is globally enabled.
public fun fee_enabled(self: &Treasury): bool {
    self.fee_enabled
}

// === Test-Only Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public(package) fun create_fee_recipient_set_event(fee_recipient: address): FeeRecipientSetEvent {
    FeeRecipientSetEvent { fee_recipient }
}

#[test_only]
public(package) fun create_native_fee_bp_set_event(native_fee_bp: u64): NativeFeeBpSetEvent {
    NativeFeeBpSetEvent { native_fee_bp }
}

#[test_only]
public(package) fun create_zro_fee_set_event(zro_fee: u64): ZroFeeSetEvent {
    ZroFeeSetEvent { zro_fee }
}

#[test_only]
public(package) fun create_zro_enabled_set_event(zro_enabled: bool): ZroEnabledSetEvent {
    ZroEnabledSetEvent { zro_enabled }
}

#[test_only]
public(package) fun create_fee_enabled_set_event(fee_enabled: bool): FeeEnabledSetEvent {
    FeeEnabledSetEvent { fee_enabled }
}
