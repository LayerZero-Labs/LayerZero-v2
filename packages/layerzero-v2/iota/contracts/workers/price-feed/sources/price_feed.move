module price_feed::price_feed;

use call::{call::Call, call_cap::{Self, CallCap}};
use price_feed_call_types::estimate_fee::{Self, EstimateFeeParam, EstimateFeeResult};
use std::u128;
use iota::{event, table::{Self, Table}};
use utils::table_ext;

// === Errors ===

const EInvalidDenominator: u64 = 1;
const ENoPrice: u64 = 2;
const ENotAnOPStack: u64 = 3;
const EOnlyPriceUpdater: u64 = 4;
const EPriceUpdaterCapNotFound: u64 = 5;

// === Model Types ===

public enum ModelType has copy, drop, store {
    DEFAULT,
    ARB_STACK,
    OP_STACK,
}

// === Structs ===

/// One time witness for the price feed package
public struct PRICE_FEED has drop {}

public struct Price has copy, drop, store {
    // Price ratio calculation: (remote_price_usd * 10^local_decimals * ratio_multiplier) / (local_price_usd *
    // 10^remote_decimals)
    // Example: IOTA ($4, 9 decimals) to BNB ($800, 18 decimals), ratio_multiplier = 10^20
    // = (800 * 10^9 * 10^20) / (4 * 10^18) = 8 * 10^31 / 4 * 10^18 = 2 * 10^13
    // This means 1 unit of BNB gas cost equals (20,000,000,000,000 / 10^20) units of IOTA gas cost
    // The denominator is typically 10^20 (price_ratio_denominator)
    price_ratio: u128,
    // Gas price per unit in the destination chain's native currency (wei for EVM, octas for Aptos, etc.)
    gas_price_in_unit: u64,
    // Gas cost per byte of calldata
    gas_per_byte: u32,
}

public struct ArbitrumPriceExt has copy, drop, store {
    gas_per_l2_tx: u64,
    gas_per_l1_call_data_byte: u32,
}

public struct OwnerCap has key, store {
    id: UID,
}

public struct PriceUpdaterCap has key {
    id: UID,
}

public struct PriceUpdaterRegistry has store {
    updater_to_updater_cap: Table<address, address>, // updater to updater_cap
    updater_cap_status: Table<address, bool>, // updater_cap to active status
}

public struct PriceFeed has key {
    id: UID,
    call_cap: CallCap,
    owner_cap: address,
    price_updater_registry: PriceUpdaterRegistry,
    default_model_price: Table<u32, Price>,
    arbitrum_price_ext: ArbitrumPriceExt,
    // Native token price in USD * price_ratio_denominator (e.g., $4 IOTA = 4 * 10^20)
    native_price_usd: u128,
    price_ratio_denominator: u128,
    // arbitrum compression - percentage of callDataSize after brotli compression
    arbitrum_compression_percent: u128,
    eid_to_model_type: Table<u32, ModelType>,
}

// === Events ===

public struct PriceUpdatedEvent has copy, drop {
    dst_eid: u32,
    price: Price,
}

public struct ArbitrumPriceExtUpdatedEvent has copy, drop {
    dst_eid: u32,
    arbitrum_price_ext: ArbitrumPriceExt,
}

public struct PriceUpdaterSetEvent has copy, drop {
    updater: address,
    active: bool,
}

public struct PriceUpdaterCapCreatedEvent has copy, drop {
    updater: address,
    updater_cap: address,
}

// === Initialization ===

fun init(otw: PRICE_FEED, ctx: &mut TxContext) {
    let owner_cap = OwnerCap { id: object::new(ctx) };
    let price_feed = PriceFeed {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&otw, ctx),
        owner_cap: object::id_address(&owner_cap),
        price_updater_registry: PriceUpdaterRegistry {
            updater_to_updater_cap: table::new(ctx),
            updater_cap_status: table::new(ctx),
        },
        default_model_price: table::new(ctx),
        arbitrum_price_ext: ArbitrumPriceExt { gas_per_l2_tx: 0, gas_per_l1_call_data_byte: 0 },
        native_price_usd: 0,
        price_ratio_denominator: u128::pow(10, 20), // 1e20 - denominator for price ratio calculations
        arbitrum_compression_percent: 47,
        eid_to_model_type: table::new(ctx),
    };

    transfer::share_object(price_feed);
    transfer::transfer(owner_cap, ctx.sender());
}

// === Create Structs ===

public fun create_price(price_ratio: u128, gas_price_in_unit: u64, gas_per_byte: u32): Price {
    Price { price_ratio, gas_price_in_unit, gas_per_byte }
}

public fun create_arbitrum_price_ext(gas_per_l2_tx: u64, gas_per_l1_call_data_byte: u32): ArbitrumPriceExt {
    ArbitrumPriceExt { gas_per_l2_tx, gas_per_l1_call_data_byte }
}

// === Create Enum For ModelType ===

public fun model_type_default(): ModelType {
    ModelType::DEFAULT
}

public fun model_type_arbitrum(): ModelType {
    ModelType::ARB_STACK
}

public fun model_type_optimism(): ModelType {
    ModelType::OP_STACK
}

// === Owner Functions ===

public fun set_price_updater(
    self: &mut PriceFeed,
    _owner: &OwnerCap,
    updater: address,
    active: bool,
    ctx: &mut TxContext,
) {
    self.ensure_price_updater_cap(updater, ctx);
    let updater_cap = self.get_price_updater_cap(updater);
    table_ext::upsert!(&mut self.price_updater_registry.updater_cap_status, updater_cap, active);
    event::emit(PriceUpdaterSetEvent { updater, active });
}

public fun set_price_ratio_denominator(self: &mut PriceFeed, _owner: &OwnerCap, denominator: u128) {
    assert!(denominator > 0, EInvalidDenominator);
    self.price_ratio_denominator = denominator;
}

public fun set_arbitrum_compression_percent(self: &mut PriceFeed, _owner: &OwnerCap, compression_percent: u128) {
    self.arbitrum_compression_percent = compression_percent;
}

public fun set_eid_to_model_type(self: &mut PriceFeed, _owner: &OwnerCap, dst_eid: u32, model_type: ModelType) {
    table_ext::upsert!(&mut self.eid_to_model_type, dst_eid, model_type);
}

// === Price Updater Functions ===

public fun set_price(self: &mut PriceFeed, updater_cap: &PriceUpdaterCap, dst_eid: u32, price: Price) {
    self.assert_price_updater(updater_cap);
    self.set_price_internal(dst_eid, price);
}

public fun set_price_for_arbitrum(
    self: &mut PriceFeed,
    updater_cap: &PriceUpdaterCap,
    dst_eid: u32,
    price: Price,
    arbitrum_price_ext: ArbitrumPriceExt,
) {
    self.assert_price_updater(updater_cap);
    self.set_price_internal(dst_eid, price);
    self.arbitrum_price_ext = arbitrum_price_ext;
    event::emit(ArbitrumPriceExtUpdatedEvent { dst_eid, arbitrum_price_ext });
}

public fun set_native_token_price_usd(
    self: &mut PriceFeed,
    updater_cap: &PriceUpdaterCap,
    native_token_price_usd: u128,
) {
    self.assert_price_updater(updater_cap);
    self.native_price_usd = native_token_price_usd;
}

// === The Core Function For Estimate Fee ===

public fun estimate_fee_by_eid(self: &PriceFeed, call: &mut Call<EstimateFeeParam, EstimateFeeResult>) {
    let param = call.param();
    let dst_eid = param.dst_eid();
    let call_data_size = param.call_data_size();
    let gas = param.gas();

    let eid = dst_eid % 30000;
    let (fee, price_ratio) = if (eid == 110 || eid == 10143 || eid == 20143) {
        self.estimate_fee_with_arbitrum_model(eid, call_data_size, gas)
    } else if (eid == 111 || eid == 10132 || eid == 20132) {
        self.estimate_fee_with_optimism_model(eid, call_data_size, gas)
    } else {
        // Check model type mapping
        let model_type = self.get_model_type(dst_eid);
        match (model_type) {
            ModelType::OP_STACK => self.estimate_fee_with_optimism_model(eid, call_data_size, gas),
            ModelType::ARB_STACK => self.estimate_fee_with_arbitrum_model(eid, call_data_size, gas),
            ModelType::DEFAULT => self.estimate_fee_with_default_model(eid, call_data_size, gas),
        }
    };
    call.complete(
        &self.call_cap,
        estimate_fee::create_result(fee as u128, price_ratio, self.price_ratio_denominator, self.native_price_usd),
    );
}

// === View Functions ===

/// Get the owner cap address of this PriceFeed
public fun get_owner_cap(self: &PriceFeed): address {
    self.owner_cap
}

public fun get_price_updater_cap(self: &PriceFeed, updater: address): address {
    *table_ext::borrow_or_abort!(&self.price_updater_registry.updater_to_updater_cap, updater, EPriceUpdaterCapNotFound)
}

public fun is_price_updater(self: &PriceFeed, updater: address): bool {
    if (self.price_updater_registry.updater_to_updater_cap.contains(updater)) {
        let updater_cap = self.price_updater_registry.updater_to_updater_cap[updater];
        *table_ext::borrow_with_default!(&self.price_updater_registry.updater_cap_status, updater_cap, &false)
    } else {
        false
    }
}

public fun get_price_ratio_denominator(self: &PriceFeed): u128 {
    self.price_ratio_denominator
}

public fun get_arbitrum_compression_percent(self: &PriceFeed): u128 {
    self.arbitrum_compression_percent
}

public fun get_model_type(self: &PriceFeed, dst_eid: u32): ModelType {
    *table_ext::borrow_with_default!(&self.eid_to_model_type, dst_eid, &ModelType::DEFAULT)
}

public fun native_token_price_usd(self: &PriceFeed): u128 {
    self.native_price_usd
}

public fun arbitrum_price_ext(self: &PriceFeed): ArbitrumPriceExt {
    self.arbitrum_price_ext
}

public fun get_price(self: &PriceFeed, dst_eid: u32): Price {
    *table_ext::borrow_or_abort!(&self.default_model_price, dst_eid, ENoPrice)
}

// === Internal Functions ===

fun estimate_fee_with_default_model(self: &PriceFeed, dst_eid: u32, call_data_size: u64, gas: u256): (u256, u128) {
    let price = get_price(self, dst_eid);
    let gas_for_call_data = (call_data_size as u256) * (price.gas_per_byte as u256);
    let remote_fee = (gas_for_call_data + gas) * (price.gas_price_in_unit as u256);
    // Convert remote chain fee to local chain equivalent using price_ratio
    // final_fee = remote_fee * price_ratio / price_ratio_denominator
    let final_fee = (remote_fee * (price.price_ratio as u256)) / (self.price_ratio_denominator as u256);
    (final_fee, price.price_ratio)
}

fun estimate_fee_with_optimism_model(self: &PriceFeed, dst_eid: u32, call_data_size: u64, gas: u256): (u256, u128) {
    let ethereum_id = get_l1_lookup_id_for_optimism_model(self, dst_eid);

    // L1 fee
    let ethereum_price = get_price(self, ethereum_id);
    let gas_for_l1_call_data = (call_data_size as u256) * (ethereum_price.gas_per_byte as u256) + 3188;
    let l1_fee = gas_for_l1_call_data * (ethereum_price.gas_price_in_unit as u256);

    // L2 fee
    let optimism_price = get_price(self, dst_eid);
    let gas_for_l2_call_data = (call_data_size as u256) * (optimism_price.gas_per_byte as u256);
    let l2_fee = (gas_for_l2_call_data + gas) * (optimism_price.gas_price_in_unit as u256);

    let l1_fee_in_src_price = (l1_fee * (ethereum_price.price_ratio as u256)) / (self.price_ratio_denominator as u256);
    let l2_fee_in_src_price = (l2_fee * (optimism_price.price_ratio as u256)) / (self.price_ratio_denominator as u256);
    let gas_fee = l1_fee_in_src_price + l2_fee_in_src_price;

    (gas_fee, optimism_price.price_ratio)
}

fun estimate_fee_with_arbitrum_model(self: &PriceFeed, dst_eid: u32, call_data_size: u64, gas: u256): (u256, u128) {
    let arbitrum_price = get_price(self, dst_eid);

    // L1 fee
    let gas_for_l1_call_data =
        (((call_data_size as u256) * (self.arbitrum_compression_percent as u256)) / 100) *
        (self.arbitrum_price_ext.gas_per_l1_call_data_byte as u256);

    // L2 fee
    let gas_for_l2_call_data = (call_data_size as u256) * (arbitrum_price.gas_per_byte as u256);
    let gas_fee =
        (gas + (self.arbitrum_price_ext.gas_per_l2_tx as u256) + gas_for_l1_call_data + gas_for_l2_call_data) *
        (arbitrum_price.gas_price_in_unit as u256);

    let final_fee = (gas_fee * (arbitrum_price.price_ratio as u256)) / (self.price_ratio_denominator as u256);
    (final_fee, arbitrum_price.price_ratio)
}

fun set_price_internal(self: &mut PriceFeed, dst_eid: u32, price: Price) {
    table_ext::upsert!(&mut self.default_model_price, dst_eid, price);
    event::emit(PriceUpdatedEvent { dst_eid, price });
}

fun get_l1_lookup_id_for_optimism_model(self: &PriceFeed, l2_eid: u32): u32 {
    let l2_eid = l2_eid % 30000;
    if (l2_eid == 111) {
        return 101
    } else if (l2_eid == 10132) {
        return 10121 // ethereum-goerli
    } else if (l2_eid == 20132) {
        return 20121 // ethereum-goerli
    };

    // Check if this EID is configured as OP_STACK model type
    assert!(self.get_model_type(l2_eid) == ModelType::OP_STACK, ENotAnOPStack);

    if (l2_eid < 10000) {
        101
    } else if (l2_eid < 20000) {
        10161 // ethereum-sepolia
    } else {
        20121 // ethereum-goerli
    }
}

fun ensure_price_updater_cap(self: &mut PriceFeed, updater: address, ctx: &mut TxContext) {
    if (!self.price_updater_registry.updater_to_updater_cap.contains(updater)) {
        let updater_cap = PriceUpdaterCap { id: object::new(ctx) };
        let updater_cap_address = object::id_address(&updater_cap);
        self.price_updater_registry.updater_to_updater_cap.add(updater, updater_cap_address);
        transfer::transfer(updater_cap, updater);
        event::emit(PriceUpdaterCapCreatedEvent { updater, updater_cap: updater_cap_address });
    }
}

fun assert_price_updater(self: &PriceFeed, updater_cap: &PriceUpdaterCap) {
    assert!(
        *table_ext::borrow_or_abort!(
            &self.price_updater_registry.updater_cap_status,
            object::id_address(updater_cap),
            EPriceUpdaterCapNotFound,
        ),
        EOnlyPriceUpdater,
    );
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(PRICE_FEED {}, ctx);
}

#[test_only]
public fun get_call_cap(self: &PriceFeed): &CallCap {
    &self.call_cap
}
