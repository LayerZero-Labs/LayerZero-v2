/// OFT Fee Management Module
///
/// This module provides destination chain specific fee calculation and management functionality for OFT (Omnichain
/// Fungible Token) transfers.
/// It implements a basis point (BPS) based fee system where fees are calculated as a percentage of the transfer amount,
/// with the ability to set different fee rates for different destination chains or use a default fee rate.
module oft::oft_fee;

use iota::{event, table::{Self, Table}};
use utils::table_ext;

// === Constants ===

/// Base fee in basis points (10,000 BPS = 100%)
/// Used as denominator in fee calculations
const BASE_FEE_BPS: u64 = 10_000;

// === Errors ===

const EInvalidFeeBps: u64 = 1;
const EInvalidFeeDepositAddress: u64 = 2;
const ENotFound: u64 = 3;
const ESameValue: u64 = 4;

// === Structs ===

/// OFT fee configuration structure with support for destination-specific fees
public struct OFTFee has store {
    /// Default fee rate in basis points (0-10,000, where 10,000 = 100%)
    /// Applied to destinations without specific fee configuration
    default_fee_bps: u64,
    /// Destination-specific fee rates mapped by endpoint ID (eid)
    fee_bps: Table<u32, u64>,
    /// Address where collected fees will be deposited
    fee_deposit_address: address,
}

// === Events ===

public struct DefaultFeeBpsSetEvent has copy, drop {
    /// Default fee rate in basis points (0-10,000, where 10,000 = 100%)
    fee_bps: u64,
}

public struct FeeBpsSetEvent has copy, drop {
    /// Destination endpoint ID
    dst_eid: u32,
    /// New fee rate in basis points (0-10,000, where 10,000 = 100%)
    fee_bps: u64,
}

public struct FeeBpsUnsetEvent has copy, drop {
    /// Destination endpoint ID
    dst_eid: u32,
}

public struct FeeDepositAddressSetEvent has copy, drop {
    /// Address where collected fees will be deposited
    fee_deposit_address: address,
}

// === Creation Functions ===

/// Creates a new OFTFee instance with zero fee rate and zero address
/// Initial state: no fees are charged and no deposit address is set
public(package) fun new(ctx: &mut TxContext): OFTFee {
    OFTFee { default_fee_bps: 0, fee_bps: table::new(ctx), fee_deposit_address: @0x0 }
}

// === Core Functions ===

/// Applies the configured fee to the given amount and returns the amount after fee deduction
///
/// **Parameters**:
/// - `dst_eid`: Destination endpoint ID to determine which fee rate to apply
/// - `amount_ld`: The original amount in local decimals
///
/// **Returns**:
/// The amount after fee deduction (original amount - calculated fee)
public(package) fun apply_fee(self: &OFTFee, dst_eid: u32, amount_ld: u64): u64 {
    assert!(self.fee_deposit_address != @0x0, EInvalidFeeDepositAddress);
    let fee_bps = self.effective_fee_bps(dst_eid);
    let preliminary_fee = ((amount_ld as u128) * (fee_bps as u128)) / (BASE_FEE_BPS as u128);
    amount_ld - (preliminary_fee as u64)
}

// === Management Functions ===

/// Sets the fee deposit address where collected fees will be sent
///
/// **Parameters**:
/// - `fee_deposit_address`: New address for fee deposits (cannot be zero address)
public(package) fun set_fee_deposit_address(self: &mut OFTFee, fee_deposit_address: address) {
    assert!(fee_deposit_address != @0x0, EInvalidFeeDepositAddress);
    assert!(self.fee_deposit_address != fee_deposit_address, ESameValue);
    self.fee_deposit_address = fee_deposit_address;
    event::emit(FeeDepositAddressSetEvent { fee_deposit_address });
}

/// Sets the default fee rate that applies to all destinations without specific configuration
///
/// **Parameters**:
/// - `fee_bps`: Default fee rate in basis points (0-10,000)
public(package) fun set_default_fee_bps(self: &mut OFTFee, fee_bps: u64) {
    assert!(fee_bps <= BASE_FEE_BPS, EInvalidFeeBps);
    assert!(self.default_fee_bps != fee_bps, ESameValue);
    self.default_fee_bps = fee_bps;
    event::emit(DefaultFeeBpsSetEvent { fee_bps });
}

/// Sets the fee rate for a specific destination chain
///
/// **Parameters**:
/// - `dst_eid`: Destination endpoint ID
/// - `fee_bps`: Fee rate in basis points (0-10,000)
public(package) fun set_fee_bps(self: &mut OFTFee, dst_eid: u32, fee_bps: u64) {
    assert!(fee_bps <= BASE_FEE_BPS, EInvalidFeeBps);
    assert!(!self.fee_bps.contains(dst_eid) || self.fee_bps[dst_eid] != fee_bps, ESameValue);
    table_ext::upsert!(&mut self.fee_bps, dst_eid, fee_bps);
    event::emit(FeeBpsSetEvent { dst_eid, fee_bps });
}

/// Unset the fee rate for a specific destination chain
///
/// **Parameters**:
/// - `dst_eid`: Destination endpoint ID
public(package) fun unset_fee_bps(self: &mut OFTFee, dst_eid: u32) {
    assert!(self.fee_bps.contains(dst_eid), ENotFound);
    self.fee_bps.remove(dst_eid);
    event::emit(FeeBpsUnsetEvent { dst_eid });
}

// === Drop Function ===

/// Drop the OFTFee instance and clean up its resources
public(package) fun drop(self: OFTFee) {
    let OFTFee { fee_bps, .. } = self;
    fee_bps.drop();
}

// === View Functions ===

/// Returns true if the OFT has a fee rate greater than 0 for the specified destination
public(package) fun has_oft_fee(self: &OFTFee, dst_eid: u32): bool {
    self.effective_fee_bps(dst_eid) > 0
}

/// Returns the effective fee rate for a specific destination chain
public(package) fun effective_fee_bps(self: &OFTFee, dst_eid: u32): u64 {
    *table_ext::borrow_with_default!(&self.fee_bps, dst_eid, &self.default_fee_bps)
}

/// Returns the default fee rate
public(package) fun default_fee_bps(self: &OFTFee): u64 {
    self.default_fee_bps
}

/// Returns the fee rate for a specific destination chain
public(package) fun fee_bps(self: &OFTFee, dst_eid: u32): u64 {
    self.fee_bps[dst_eid]
}

/// Returns the current fee deposit address
public(package) fun fee_deposit_address(self: &OFTFee): address {
    self.fee_deposit_address
}
