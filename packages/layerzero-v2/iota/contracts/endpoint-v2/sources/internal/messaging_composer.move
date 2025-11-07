/// Messaging Composer
///
/// This module manages the composition messaging system within LayerZero V2, which enables
/// sequential execution of multiple actions after a cross-chain message is received.
/// Compose messages allow OApps to trigger additional operations on the destination chain
/// after the initial lz_receive execution completes.
///
/// **Flow:**
/// 1. OApp calls send_compose() during or after lz_receive to queue a compose message
/// 2. Message hash is stored in the composer's queue
/// 3. Executor calls lz_compose() to process the queued message
/// 4. clear_compose() marks the message as delivered and prevents re-execution
module endpoint_v2::messaging_composer;

use std::ascii::String;
use iota::{event, table::{Self, Table}};
use utils::{bytes32::{Self, Bytes32}, hash, table_ext};

// === Errors ===

const EComposeExists: u64 = 1;
const EComposeMessageMismatch: u64 = 2;
const EComposeNotFound: u64 = 3;
const EComposerNotRegistered: u64 = 4;
const EComposerRegistered: u64 = 5;

// === Structs ===

/// Global registry that manages composer registrations and their metadata.
/// Similar to OAppRegistry but specifically for compose message handlers.
public struct ComposerRegistry has store {
    // Maps composer package address to its complete information
    composers: Table<address, ComposerRegistration>,
}

/// Stores the complete registration information for a composer.
/// This information is used throughout the system to:
/// - Route compose messages to the correct queue
/// - Validate that operations come from legitimate composers
/// - Track the composer information for the composer, including the lz_compose execution information
public struct ComposerRegistration has store {
    // The address of the compose queue object that this composer uses to manage pending messages
    compose_queue: address,
    // The composer information for the composer
    composer_info: vector<u8>,
}

/// Shared object that manages compose message queues for a specific composer.
/// Each composer gets its own ComposeQueue to enable parallel transaction execution.
public struct ComposeQueue has key {
    id: UID,
    // The composer address that owns this compose queue
    composer: address,
    // Queue of pending compose messages: (from, guid, index) -> message_hash
    messages: Table<MessageKey, Bytes32>,
}

/// Composite key for identifying a specific compose message in the queue.
public struct MessageKey has copy, drop, store {
    // The OApp address that sent the compose message
    from: address,
    // The GUID of the original cross-chain message that triggered this compose
    guid: Bytes32,
    // The index of this compose message (multiple compose messages can share a GUID)
    index: u16,
}

// === Events ===

public struct ComposeSentEvent has copy, drop {
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
}

public struct ComposeDeliveredEvent has copy, drop {
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
}

public struct LzComposeAlertEvent has copy, drop {
    from: address,
    to: address,
    executor: address,
    guid: Bytes32,
    index: u16,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
}

public struct ComposerRegisteredEvent has copy, drop {
    composer: address,
    compose_queue: address,
    composer_info: vector<u8>,
}

public struct ComposerInfoSetEvent has copy, drop {
    composer: address,
    composer_info: vector<u8>,
}

// === Creation ===

/// Creates a new empty ComposerRegistry.
public(package) fun new_composer_registry(ctx: &mut TxContext): ComposerRegistry {
    ComposerRegistry { composers: table::new(ctx) }
}

// === Package Functions ===

/// Registers a new composer with its metadata and creates its messaging composer.
/// This establishes the composer's ability to receive and process compose messages.
public(package) fun register_composer(
    self: &mut ComposerRegistry,
    composer: address,
    composer_info: vector<u8>,
    ctx: &mut TxContext,
): address {
    assert!(!self.is_registered(composer), EComposerRegistered);

    let compose_queue = ComposeQueue { id: object::new(ctx), composer, messages: table::new(ctx) };
    let compose_queue_address = object::id_address(&compose_queue);
    self
        .composers
        .add(
            composer,
            ComposerRegistration { compose_queue: compose_queue_address, composer_info },
        );

    // Each composer has its own compose_queue shared object to enable parallel execution
    transfer::share_object(compose_queue);
    event::emit(ComposerRegisteredEvent {
        composer,
        compose_queue: compose_queue_address,
        composer_info,
    });

    compose_queue_address
}

/// Updates the composer execution information for a registered composer.
/// This allows composers to modify their information after registration.
public(package) fun set_composer_info(self: &mut ComposerRegistry, composer: address, composer_info: vector<u8>) {
    let registration = table_ext::borrow_mut_or_abort!(&mut self.composers, composer, EComposerNotRegistered);
    registration.composer_info = composer_info;
    event::emit(ComposerInfoSetEvent { composer, composer_info });
}

// === Core Functions ===

/// Queues a compose message for later execution.
/// Called by OApps during or after lz_receive to trigger additional operations.
public(package) fun send_compose(
    self: &mut ComposeQueue,
    from: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
) {
    let key = MessageKey { from, guid, index };
    assert!(!self.messages.contains(key), EComposeExists);
    self.messages.add(key, hash::keccak256!(&message));
    event::emit(ComposeSentEvent { from, to: self.composer, guid, index, message });
}

/// Clears a compose message after successful execution.
/// Verifies the message hash matches what was stored, then marks it as delivered
/// by setting the hash to 0xff to prevent re-sending.
public(package) fun clear_compose(
    self: &mut ComposeQueue,
    from: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
) {
    let key = MessageKey { from, guid, index };
    assert!(self.messages.contains(key), EComposeNotFound);

    // Verify message integrity by comparing hashes
    let stored_hash = self.messages.borrow_mut(key);
    let actual_hash = hash::keccak256!(&message);
    assert!(*stored_hash == actual_hash, EComposeMessageMismatch);

    // Mark as delivered to prevent re-execution
    *stored_hash = bytes32::ff_bytes32();
    event::emit(ComposeDeliveredEvent { from, to: self.composer, guid, index });
}

/// Emits an alert event when lz_compose execution fails.
/// Called by executors to log failed compose message delivery attempts.
public(package) fun lz_compose_alert(
    executor: address,
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
) {
    event::emit(LzComposeAlertEvent { from, to, executor, guid, index, gas, value, message, extra_data, reason });
}

// === Composer Registry View Functions ===

/// Checks if a composer is fully registered in the system.
/// A composer is considered registered if it has both package and messaging composer entries.
public(package) fun is_registered(self: &ComposerRegistry, composer: address): bool {
    self.composers.contains(composer)
}

/// Gets the compose queue address for a registered composer.
/// The compose queue is used for managing compose message queues and parallel execution.
public(package) fun get_compose_queue(self: &ComposerRegistry, composer: address): address {
    let registration = table_ext::borrow_or_abort!(&self.composers, composer, EComposerNotRegistered);
    registration.compose_queue
}

/// Gets the composer execution information for a registered composer.
/// This contains version and payload data needed for compose message execution.
public(package) fun get_composer_info(self: &ComposerRegistry, composer: address): &vector<u8> {
    let registration = table_ext::borrow_or_abort!(&self.composers, composer, EComposerNotRegistered);
    &registration.composer_info
}

// === Compose Queue View Functions ===

/// Returns the composer package address that owns this compose queue.
public(package) fun composer(self: &ComposeQueue): address {
    self.composer
}

/// Checks if a compose message exists in the queue.
public(package) fun has_compose_message_hash(self: &ComposeQueue, from: address, guid: Bytes32, index: u16): bool {
    self.messages.contains(MessageKey { from, guid, index })
}

/// Gets the stored hash for a specific compose message.
/// Used to verify message integrity during execution.
public(package) fun get_compose_message_hash(self: &ComposeQueue, from: address, guid: Bytes32, index: u16): Bytes32 {
    *table_ext::borrow_or_abort!(&self.messages, MessageKey { from, guid, index }, EComposeNotFound)
}

// === Testing Helpers ===

#[test_only]
public(package) fun get_compose_queue_length(self: &ComposeQueue): u64 {
    table::length(&self.messages)
}

#[test_only]
public(package) fun create_compose_sent_event(
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
): ComposeSentEvent {
    ComposeSentEvent { from, to, guid, index, message }
}

#[test_only]
public(package) fun create_compose_delivered_event(
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
): ComposeDeliveredEvent {
    ComposeDeliveredEvent { from, to, guid, index }
}

#[test_only]
public(package) fun create_lz_compose_alert_event(
    executor: address,
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
): LzComposeAlertEvent {
    LzComposeAlertEvent { from, to, executor, guid, index, gas, value, message, extra_data, reason }
}

#[test_only]
public(package) fun create_composer_registered_event(
    composer: address,
    compose_queue: address,
    composer_info: vector<u8>,
): ComposerRegisteredEvent {
    ComposerRegisteredEvent { composer, compose_queue, composer_info }
}

#[test_only]
public(package) fun create_composer_info_set_event(composer: address, composer_info: vector<u8>): ComposerInfoSetEvent {
    ComposerInfoSetEvent { composer, composer_info }
}

#[test_only]
public fun get_compose_sent_event_from(self: &ComposeSentEvent): address {
    self.from
}

#[test_only]
public fun get_compose_sent_event_to(self: &ComposeSentEvent): address {
    self.to
}

#[test_only]
public fun get_compose_sent_event_guid(self: &ComposeSentEvent): Bytes32 {
    self.guid
}

#[test_only]
public fun get_compose_sent_event_index(self: &ComposeSentEvent): u16 {
    self.index
}

#[test_only]
public fun get_compose_sent_event_message(self: &ComposeSentEvent): vector<u8> {
    self.message
}
