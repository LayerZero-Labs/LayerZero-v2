module counter::counter;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use counter::{msg_codec, options_builder};
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2},
    lz_compose::LzComposeParam,
    lz_receive::LzReceiveParam,
    messaging_composer::ComposeQueue,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    utils
};
use oapp::{endpoint_calls, oapp::{Self, OApp, AdminCap}, oapp_info_v1};
use sui::{coin::{Self, Coin}, sui::SUI, table::{Self, Table}};
use utils::{bytes32::Bytes32, package, table_ext};
use zro::zro::ZRO;

// === Constants ===

const VANILLA_TYPE: u8 = 1;
const COMPOSED_TYPE: u8 = 2;
const ABA_TYPE: u8 = 3;
const COMPOSED_ABA_TYPE: u8 = 4;

// === Errors ===

const EInvalidMsgType: u64 = 0;
const EInvalidValue: u64 = 1;
const EInvalidNonce: u64 = 2;
const EOnlyEndpoint: u64 = 3;
const ESelfComposeOnly: u64 = 4;
const EInvalidOApp: u64 = 5;

// === Structs ===

/// One-time witness for the Counter package
public struct COUNTER has drop {}

public struct NonceKey has copy, drop, store {
    src_eid: u32,
    sender: Bytes32,
}

public struct Counter has key, store {
    id: UID,
    eid: u32,
    oapp: address,
    call_cap: CallCap,
    composer_cap: CallCap,
    count: u64,
    composed_count: u64,
    outbound_count: Table<u32, u64>,
    inbound_count: Table<u32, u64>,
    // OrderNonce related fields
    max_received_nonce: Table<NonceKey, u64>,
    ordered_nonce: bool,
    refund_address: address,
}

// === Initialization ===

fun init(otw: COUNTER, ctx: &mut TxContext) {
    let (call_cap, admin_cap, oapp) = oapp::new(&otw, ctx);
    let composer_cap = call_cap::new_package_cap(&otw, ctx);
    let counter = Counter {
        id: object::new(ctx),
        eid: 0,
        oapp,
        call_cap,
        composer_cap,
        count: 0,
        composed_count: 0,
        outbound_count: table::new(ctx),
        inbound_count: table::new(ctx),
        // OrderNonce related fields
        max_received_nonce: table::new(ctx),
        ordered_nonce: false,
        refund_address: ctx.sender(),
    };
    transfer::share_object(counter);
    transfer::public_transfer(admin_cap, ctx.sender());
}

public fun init_counter(
    self: &mut Counter,
    oapp: &mut OApp,
    admin_cap: &AdminCap,
    endpoint: &mut EndpointV2,
    lz_receive_info: vector<u8>,
    lz_compose_info: vector<u8>,
    ctx: &mut TxContext,
) {
    self.assert_oapp(oapp);
    oapp.assert_admin(admin_cap);

    self.eid = endpoint.eid();
    let oapp_info = oapp_info_v1::create(
        object::id_address(oapp),
        vector[],
        lz_receive_info,
        b"this is a counter",
    );
    // register the counter(as oapp) to the endpoint
    endpoint_calls::register_oapp(oapp, admin_cap, endpoint, oapp_info.encode(), ctx);
    // register the counter(as composer) to the endpoint
    endpoint.register_composer(&self.composer_cap, lz_compose_info, ctx);
}

// === Public Functions ===

public fun quote(
    self: &Counter,
    oapp: &OApp,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    pay_in_zro: bool,
    ctx: &mut TxContext,
): Call<EndpointQuoteParam, MessagingFee> {
    assert_msg_type(msg_type);
    self.assert_oapp(oapp);
    let message = msg_codec::encode_msg(msg_type, self.eid, 0);
    let combined_options = oapp.combine_options(dst_eid, msg_type as u16, options);
    oapp.quote(&self.call_cap, dst_eid, message, combined_options, pay_in_zro, ctx)
}

public fun increment(
    self: &mut Counter,
    oapp: &OApp,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    native_coin: Coin<SUI>,
    zro_coin: Option<Coin<ZRO>>,
    refund_address: address,
    ctx: &mut TxContext,
): Call<EndpointSendParam, MessagingReceipt> {
    assert_msg_type(msg_type);
    self.assert_oapp(oapp);
    self.increment_outbound_count(dst_eid);
    let message = msg_codec::encode_msg(msg_type, self.eid, 0);
    let combined_options = oapp.combine_options(dst_eid, msg_type as u16, options);
    oapp.lz_send_and_refund(
        &self.call_cap,
        dst_eid,
        message,
        combined_options,
        native_coin,
        zro_coin,
        refund_address,
        ctx,
    )
}

public fun lz_receive(
    self: &mut Counter,
    oapp: &OApp,
    compose_queue: &mut ComposeQueue,
    call: Call<LzReceiveParam, Void>,
    ctx: &mut TxContext,
) {
    self.assert_oapp(oapp);
    let (src_eid, guid, message, msg_type, msg_value, receive_coin) = process_lz_receive(self, oapp, call, ctx);
    assert!(msg_type != ABA_TYPE, EInvalidMsgType); // ABA mode should be handled by lz_receive_aba()

    // Handle business logic
    if (msg_type == VANILLA_TYPE) {
        self.increment_inbound_count(src_eid);
        // ================================== IMPORTANT ==================================
        // if you request for msg.value in the options, you should also encode it
        // into your message and check the value received at destination (example below).
        // if not, the executor could potentially provide less msg.value than you requested
        // leading to unintended behavior. Another option is to assert the executor to be
        // one that you trust.
        // ================================================================================
        assert!(receive_coin.value() as u256 >= msg_value, EInvalidValue);
    } else if (msg_type == COMPOSED_TYPE || msg_type == COMPOSED_ABA_TYPE) {
        self.increment_inbound_count(src_eid);
        assert!(endpoint_v2::get_composer(compose_queue) == self.composer_address(), ESelfComposeOnly);
        endpoint_v2::send_compose(&self.call_cap, compose_queue, guid, 0, message);
    } else {
        abort EInvalidMsgType
    };

    utils::transfer_coin(receive_coin, self.refund_address); // transfer the value to the refund_address
}

public fun lz_receive_aba(
    self: &mut Counter,
    oapp: &OApp,
    call: Call<LzReceiveParam, Void>,
    ctx: &mut TxContext,
): Call<EndpointSendParam, MessagingReceipt> {
    self.assert_oapp(oapp);
    let (src_eid, _, _, msg_type, msg_value, receive_coin) = process_lz_receive(self, oapp, call, ctx);

    assert!(msg_type == ABA_TYPE, EInvalidMsgType);
    assert!(receive_coin.value() as u256 >= msg_value, EInvalidValue);

    // A -> B: Inbound logic
    self.increment_inbound_count(src_eid);

    // B -> A: Outbound logic
    self.increment_outbound_count(src_eid);
    let message = msg_codec::encode_msg(VANILLA_TYPE, self.eid, 10);
    let options: vector<u8> = options_builder::new_builder().add_executor_lz_receive_option(200000, 10).build();

    let combined_options = oapp.combine_options(src_eid, VANILLA_TYPE as u16, options);
    // use all the received _coin for the native fee, the left will be refunded to the refund_address
    oapp.lz_send_and_refund(
        &self.call_cap,
        src_eid,
        message,
        combined_options,
        receive_coin,
        option::none(),
        self.refund_address,
        ctx,
    )
}

public fun lz_compose(self: &mut Counter, call: Call<LzComposeParam, Void>, ctx: &mut TxContext) {
    assert!(call.caller() == package::original_package_of_type<EndpointV2>(), EOnlyEndpoint);
    let param = call.complete_and_destroy(&self.composer_cap);
    let (from, _guid, message, _executor, _extra_data, value) = param.destroy();
    assert!(from == self.call_cap_address(), ESelfComposeOnly);
    let receive_coin = value.destroy_or!(coin::zero<SUI>(ctx));

    let msg_value = msg_codec::get_value(&message);
    // ================================== IMPORTANT ==================================
    // if you request for msg.value in the options, you should also encode it
    // into your message and check the value received at destination (example below).
    // if not, the executor could potentially provide less msg.value than you requested
    // leading to unintended behavior. Another option is to assert the executor to be
    // one that you trust.
    // ================================================================================
    assert!(receive_coin.value() as u256 >= msg_value, EInvalidValue);

    // Handle business logic
    let msg_type = msg_codec::get_msg_type(&message);
    assert!(msg_type == COMPOSED_TYPE, EInvalidMsgType);
    self.increment_composed_count();
    utils::transfer_coin(receive_coin, self.refund_address); // transfer the value to the refund_address
}

public fun lz_compose_aba(
    self: &mut Counter,
    oapp: &OApp,
    call: Call<LzComposeParam, Void>,
    ctx: &mut TxContext,
): Call<EndpointSendParam, MessagingReceipt> {
    assert!(call.caller() == package::original_package_of_type<EndpointV2>(), EOnlyEndpoint);
    self.assert_oapp(oapp);
    let param = call.complete_and_destroy(&self.composer_cap);
    let (_from, _guid, message, _executor, _extra_data, value) = param.destroy();
    let receive_coin = value.destroy_or!(coin::zero<SUI>(ctx));

    let msg_value = msg_codec::get_value(&message);
    // ================================== IMPORTANT ==================================
    // if you request for msg.value in the options, you should also encode it
    // into your message and check the value received at destination (example below).
    // if not, the executor could potentially provide less msg.value than you requested
    // leading to unintended behavior. Another option is to assert the executor to be
    // one that you trust.
    // ================================================================================
    assert!(receive_coin.value() as u256 >= msg_value, EInvalidValue);

    // Handle business logic
    let msg_type = msg_codec::get_msg_type(&message);
    assert!(msg_type == COMPOSED_ABA_TYPE, EInvalidMsgType);

    let src_eid = msg_codec::get_src_eid(&message);
    self.increment_composed_count();
    self.increment_outbound_count(src_eid);

    let options: vector<u8> = options_builder::new_builder().add_executor_lz_receive_option(200000, 10).build();

    let combined_options = oapp.combine_options(src_eid, VANILLA_TYPE as u16, options);
    // use all the received _coin for the native fee, the left will be refunded to the refund_address
    oapp.lz_send_and_refund(
        &self.call_cap,
        src_eid,
        message,
        combined_options,
        receive_coin,
        option::none(),
        self.refund_address,
        ctx,
    )
}

// === Endpoint Configuration For Composer ===

public fun set_composer_info(
    self: &Counter,
    oapp: &OApp,
    admin: &AdminCap,
    endpoint: &mut EndpointV2,
    composer_info: vector<u8>,
) {
    self.assert_oapp(oapp);
    oapp.assert_admin(admin);
    endpoint.set_composer_info(&self.composer_cap, composer_info);
}

// View fucntion

public fun eid(self: &Counter): u32 {
    self.eid
}

public fun call_cap_address(self: &Counter): address {
    self.call_cap.id()
}

public fun composer_address(self: &Counter): address {
    self.composer_cap.id()
}

public fun get_count(self: &Counter): u64 {
    self.count
}

public fun get_composed_count(self: &Counter): u64 {
    self.composed_count
}

public fun get_outbound_count(self: &Counter, dst_eid: u32): u64 {
    *table_ext::borrow_with_default!(&self.outbound_count, dst_eid, &0)
}

public fun get_inbound_count(self: &Counter, src_eid: u32): u64 {
    *table_ext::borrow_with_default!(&self.inbound_count, src_eid, &0)
}

public fun next_nonce(self: &Counter, src_eid: u32, sender: Bytes32): u64 {
    if (self.ordered_nonce) {
        let nonce_key = NonceKey { src_eid, sender };
        let current_nonce = *table_ext::borrow_with_default!(&self.max_received_nonce, nonce_key, &0);
        current_nonce + 1
    } else {
        0 // path nonce starts from 1. if 0 it means that there is no specific nonce enforcement
    }
}

public fun get_max_received_nonce(self: &Counter, src_eid: u32, sender: Bytes32): u64 {
    let nonce_key = NonceKey { src_eid, sender };
    *table_ext::borrow_with_default!(&self.max_received_nonce, nonce_key, &0)
}

public fun is_ordered_nonce(self: &Counter): bool {
    self.ordered_nonce
}

// === Internal Functions ===

public fun assert_oapp(self: &Counter, oapp: &OApp) {
    assert!(object::id_address(oapp) == self.oapp, EInvalidOApp);
}

public fun assert_oapp_admin(self: &Counter, oapp: &OApp, admin: &AdminCap) {
    self.assert_oapp(oapp);
    oapp.assert_admin(admin);
}

fun assert_msg_type(msg_type: u8) {
    assert!(
        msg_type == VANILLA_TYPE || msg_type == ABA_TYPE || msg_type == COMPOSED_TYPE || msg_type == COMPOSED_ABA_TYPE,
        EInvalidMsgType,
    );
}

/// Process a LayerZero receive call and extract common parameters
/// Returns (src_eid, sender, nonce, guid, message, msg_type, msg_value, receive_coin)
fun process_lz_receive(
    self: &mut Counter,
    oapp: &OApp,
    call: Call<LzReceiveParam, Void>,
    ctx: &mut TxContext,
): (u32, Bytes32, vector<u8>, u8, u256, Coin<SUI>) {
    let param = oapp.lz_receive(&self.call_cap, call);
    let (src_eid, sender, nonce, guid, message, _, _, value) = param.destroy();
    let msg_value = msg_codec::get_value(&message);
    let receive_coin = value.destroy_or!(coin::zero<SUI>(ctx));

    // OrderNonce: validate and update nonce
    self.accept_nonce(src_eid, sender, nonce);

    let msg_type = msg_codec::get_msg_type(&message);

    (src_eid, guid, message, msg_type, msg_value, receive_coin)
}

fun accept_nonce(self: &mut Counter, src_eid: u32, sender: Bytes32, nonce: u64) {
    let nonce_key = NonceKey { src_eid, sender };
    let current_nonce = *table_ext::borrow_with_default!(&self.max_received_nonce, nonce_key, &0);

    if (self.ordered_nonce) {
        assert!(nonce == current_nonce + 1, EInvalidNonce);
    };

    // Update the max nonce anyway. Once the ordered mode is turned on, missing early nonces will be rejected
    if (nonce > current_nonce) {
        table_ext::upsert!(&mut self.max_received_nonce, nonce_key, nonce);
    };
}

fun increment_outbound_count(self: &mut Counter, dst_eid: u32) {
    let outbound_count: u64 = get_outbound_count(self, dst_eid);
    table_ext::upsert!(&mut self.outbound_count, dst_eid, outbound_count+1);
}

fun increment_inbound_count(self: &mut Counter, src_eid: u32) {
    let inbound_count: u64 = get_inbound_count(self, src_eid);
    table_ext::upsert!(&mut self.inbound_count, src_eid, inbound_count+1);
    self.count = self.count + 1;
}

fun increment_composed_count(self: &mut Counter) {
    self.composed_count = self.composed_count + 1;
}

// === Test Functions ===

#[test_only]
use sui::test_scenario::{Scenario};

#[test_only]
public fun init_for_test(scenario: &mut Scenario) {
    let ctx = scenario.ctx();
    let call_cap = call_cap::new_package_cap_for_test(ctx);
    let admin_cap = oapp::create_admin_cap_for_test(ctx);
    let oapp = oapp::create_oapp_for_test(&call_cap, &admin_cap, ctx);
    let composer_cap = call_cap::new_package_cap_for_test(ctx);
    let counter = Counter {
        id: object::new(ctx),
        eid: 0,
        oapp: object::id_address(&oapp),
        call_cap,
        composer_cap,
        count: 0,
        composed_count: 0,
        outbound_count: table::new(ctx),
        inbound_count: table::new(ctx),
        // OrderNonce related fields
        max_received_nonce: table::new(ctx),
        ordered_nonce: false,
        refund_address: ctx.sender(),
    };
    oapp::share_oapp_for_test(oapp);
    transfer::share_object(counter);
    transfer::public_transfer(admin_cap, ctx.sender());
}

#[test_only]
public fun init_counter_for_test(
    self: &mut Counter,
    oapp: &mut OApp,
    admin_cap: &AdminCap,
    endpoint: &mut EndpointV2,
    lz_receive_info: vector<u8>,
    lz_compose_info: vector<u8>,
    ctx: &mut TxContext,
) {
    self.assert_oapp(oapp);
    oapp.assert_admin(admin_cap);

    self.eid = endpoint.eid();
    // register the counter(as oapp) to the endpoint
    endpoint.register_oapp(&self.call_cap, lz_receive_info, ctx);
    // register the counter(as composer) to the endpoint
    endpoint.register_composer(&self.composer_cap, lz_compose_info, ctx);
}
