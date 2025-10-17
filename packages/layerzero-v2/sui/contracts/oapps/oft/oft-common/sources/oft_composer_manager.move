/// OFT Composer Manager
///
/// This module manages the registration and routing of compose transfers within the OFT ecosystem.
/// It serves as the central registry for composer contracts and their associated deposit addresses,
/// enabling secure and traceable token transfers for compose operations.
module oft_common::oft_composer_manager;

use call::call_cap::CallCap;
use oft_common::compose_transfer;
use sui::{coin::Coin, event, table::{Self, Table}};
use utils::{bytes32::Bytes32, table_ext};

// === Errors ===

const EComposeTransferNotFound: u64 = 1;
const EDepositAddressNotFound: u64 = 2;
const EInvalidDepositAddress: u64 = 3;

// === Structs ===

/// Central registry managing compose transfers and deposit addresses for OFT composer contracts.
public struct OFTComposerManager has key {
    id: UID,
    /// Maps composer contract addresses to their designated deposit addresses
    deposit_addresses: Table<address, address>,
    /// Maps unique transfer keys to ComposeTransfer object addresses for retrieval
    compose_transfers: Table<TransferKey, address>,
}

/// Composite key uniquely identifying a compose transfer within the registry.
public struct TransferKey has copy, drop, store {
    /// Address that OFT contract initiating the compose transfer
    from: address,
    /// LayerZero message GUID linking to the original cross-chain transfer
    guid: Bytes32,
    /// Target composer contract that will receive and process the tokens
    composer: address,
}

// === Events ===

public struct DepositAddressSetEvent has copy, drop {
    /// Composer contract address that registered the deposit address
    composer: address,
    /// Designated address where compose transfers should be sent
    deposit_address: address,
}

public struct ComposeTransferSentEvent has copy, drop {
    /// Address that OFT contract initiating the compose transfer
    from: address,
    /// LayerZero message GUID linking to the original cross-chain transfer
    guid: Bytes32,
    /// Composer contract that will execute the compose logic
    composer: address,
    /// Actual destination address where the ComposeTransfer object was sent
    deposit_address: address,
    /// Object ID of the created ComposeTransfer for tracking and retrieval
    transfer_id: address,
}

// === Initialization ===

/// Initializes the global OFT composer registry as a shared object.
/// Called once during module deployment to create the singleton registry instance.
fun init(ctx: &mut TxContext) {
    let manager = OFTComposerManager {
        id: object::new(ctx),
        deposit_addresses: table::new(ctx),
        compose_transfers: table::new(ctx),
    };
    transfer::share_object(manager);
}

// === Main Functions ===

/// Registers or updates the deposit address for a composer contract.
///
/// **Parameters**:
/// - `composer`: CallCap proving authorization to act on behalf of the composer contract
/// - `deposit_address`: Address where ComposeTransfer objects should be sent for this composer
public fun set_deposit_address(self: &mut OFTComposerManager, composer: &CallCap, deposit_address: address) {
    assert!(deposit_address != @0x0, EInvalidDepositAddress);
    table_ext::upsert!(&mut self.deposit_addresses, composer.id(), deposit_address);
    event::emit(DepositAddressSetEvent { composer: composer.id(), deposit_address });
}

/// Routes tokens to a composer contract for compose execution.
///
/// **Parameters**:
/// - `from`: CallCap of the OFT contract initiating the compose transfer
/// - `guid`: LayerZero message GUID linking to the original cross-chain transfer
/// - `composer`: Address of the target composer contract
/// - `coin`: Tokens to be sent for compose execution
///
/// **Requirements**: Composer must have a registered deposit address
public fun send_to_composer<T>(
    self: &mut OFTComposerManager,
    from: &CallCap,
    guid: Bytes32,
    composer: address,
    coin: Coin<T>,
    ctx: &mut TxContext,
) {
    // Build the ComposeTransfer object
    let compose_transfer = compose_transfer::create(from.id(), guid, coin, ctx);
    let transfer_id = object::id_address(&compose_transfer);
    table_ext::upsert!(&mut self.compose_transfers, TransferKey { from: from.id(), guid, composer }, transfer_id);

    // Send the ComposeTransfer object to the deposit address of the composer
    let deposit_address = self.get_deposit_address(composer);
    transfer::public_transfer(compose_transfer, deposit_address);

    // Emit the event
    event::emit(ComposeTransferSentEvent { from: from.id(), guid, composer, deposit_address, transfer_id });
}

// === View Functions ===

/// Retrieves the registered deposit address for a composer contract.
public fun get_deposit_address(self: &OFTComposerManager, composer: address): address {
    *table_ext::borrow_or_abort!(&self.deposit_addresses, composer, EDepositAddressNotFound)
}

/// Retrieves the ComposeTransfer object address for a specific transfer.
public fun get_compose_transfer(self: &OFTComposerManager, from: address, guid: Bytes32, composer: address): address {
    *table_ext::borrow_or_abort!(
        &self.compose_transfers,
        TransferKey { from, guid, composer },
        EComposeTransferNotFound,
    )
}

// === Test-Only Functions ===

#[test_only]
/// Creates and shares a new OFTComposerManager for testing purposes.
/// This mimics the behavior of the init function but allows explicit control in tests.
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
