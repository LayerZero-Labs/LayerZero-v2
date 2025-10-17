module oft_composer_example::oft_composer;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{endpoint_v2::EndpointV2, lz_compose::LzComposeParam, utils};
use oft_common::{compose_transfer::ComposeTransfer, oft_compose_msg_codec, oft_composer_manager::OFTComposerManager};
use oft_composer_example::custom_compose_codec;
use sui::transfer::Receiving;
use utils::package;

const EOnlyEndpoint: u64 = 1;
const EInvalidPaymentFrom: u64 = 2;
const EInvalidPaymentGuid: u64 = 3;
const EInvalidAmount: u64 = 4;

public struct AdminCap has key, store {
    id: UID,
}

public struct OFTComposer has key {
    id: UID,
    composer_cap: CallCap,
}

public struct OFT_COMPOSER has drop {}

fun init(otw: OFT_COMPOSER, ctx: &mut TxContext) {
    let composer_cap = call_cap::new_package_cap(&otw, ctx);
    let oft_composer = OFTComposer {
        id: object::new(ctx),
        composer_cap,
    };
    transfer::share_object(oft_composer);
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun lz_compose<T>(
    self: &mut OFTComposer,
    receiving: Receiving<ComposeTransfer<T>>,
    call: Call<LzComposeParam, Void>,
    ctx: &mut TxContext,
) {
    assert!(call.caller() == package::original_package_of_type<EndpointV2>(), EOnlyEndpoint);
    let param = call.complete_and_destroy(&self.composer_cap);

    let (from, guid, message, _, _, compose_value) = param.destroy();
    let payment = transfer::public_receive(&mut self.id, receiving);
    let (payment_from, payment_guid, coin) = payment.destroy();
    let compose_msg = oft_compose_msg_codec::decode(&message);

    // check if the payment is issued from the designated OFT
    assert!(from == payment_from, EInvalidPaymentFrom);
    assert!(guid == payment_guid, EInvalidPaymentGuid);
    assert!(compose_msg.amount_ld() == coin.value(), EInvalidAmount);

    let recipient = custom_compose_codec::decode(compose_msg.compose_msg());

    utils::transfer_coin(coin, recipient);
    utils::transfer_coin_option(compose_value, ctx.sender());
}

public fun register_composer(
    self: &mut OFTComposer,
    _admin_cap: &AdminCap,
    endpoint: &mut EndpointV2,
    composer_info: vector<u8>,
    ctx: &mut TxContext,
): address {
    endpoint.register_composer(&self.composer_cap, composer_info, ctx)
}

public fun set_composer_info(
    self: &mut OFTComposer,
    _admin_cap: &AdminCap,
    endpoint: &mut EndpointV2,
    composer_info: vector<u8>,
) {
    endpoint.set_composer_info(&self.composer_cap, composer_info)
}

public fun set_deposit_address(
    self: &mut OFTComposer,
    _admin_cap: &AdminCap,
    composer_registry: &mut OFTComposerManager,
    deposit_address: address,
) {
    composer_registry.set_deposit_address(&self.composer_cap, deposit_address);
}

public fun composer_address(self: &OFTComposer): address {
    self.composer_cap.id()
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(OFT_COMPOSER {}, ctx);
}

#[test_only]
public fun composer_cap(self: &OFTComposer): &CallCap {
    &self.composer_cap
}

#[test_only]
public fun register_composer_for_test(
    self: &mut OFTComposer,
    _admin_cap: &AdminCap,
    endpoint: &mut EndpointV2,
    composer_info: vector<u8>,
    ctx: &mut TxContext,
): address {
    endpoint.register_composer(&self.composer_cap, composer_info, ctx)
}
