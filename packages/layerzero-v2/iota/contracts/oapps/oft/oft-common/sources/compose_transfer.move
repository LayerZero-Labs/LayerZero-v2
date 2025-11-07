/// Compose Transfer Data Structure
///
/// This module defines the ComposeTransfer object that wraps tokens sent to composers
/// for compose execution. It preserves the original transfer context and metadata,
/// enabling composers to execute complex cross-chain workflows with full traceability.
module oft_common::compose_transfer;

use iota::coin::Coin;
use utils::bytes32::Bytes32;

// === Structs ===

/// Transferable object containing tokens and metadata for compose execution.
#[allow(lint(coin_field))]
public struct ComposeTransfer<phantom T> has key, store {
    /// Unique object identifier for this compose transfer instance
    id: UID,
    /// Address that OFT contract initiating the compose transfer
    from: address,
    /// LayerZero message GUID linking to the original cross-chain transfer
    guid: Bytes32,
    /// Tokens to be used for compose execution
    coin: Coin<T>,
}

// === Creation ===

/// Creates a new ComposeTransfer object wrapping tokens and transfer metadata.
///
/// **Parameters**:
/// - `from`: Address that OFT contract initiating the compose transfer
/// - `guid`: LayerZero message GUID from the original transfer
/// - `coin`: Tokens to be wrapped for compose execution
///
/// **Returns**: ComposeTransfer object ready for transfer to composer
public(package) fun create<T>(from: address, guid: Bytes32, coin: Coin<T>, ctx: &mut TxContext): ComposeTransfer<T> {
    ComposeTransfer { id: object::new(ctx), from, guid, coin }
}

// === Destruction ===

/// Unpacks a ComposeTransfer object, extracting tokens and metadata for compose execution.
public fun destroy<T>(self: ComposeTransfer<T>): (address, Bytes32, Coin<T>) {
    let ComposeTransfer { id, from, guid, coin } = self;
    object::delete(id);
    (from, guid, coin)
}

// === Getters ===

/// Returns the address that initiated the original cross-chain transfer.
public fun from<T>(self: &ComposeTransfer<T>): address {
    self.from
}

/// Returns the LayerZero message GUID linking to the original cross-chain transfer.
public fun guid<T>(self: &ComposeTransfer<T>): Bytes32 {
    self.guid
}

/// Returns a reference to the wrapped tokens for inspection without consuming the object.
public fun coin<T>(self: &ComposeTransfer<T>): &Coin<T> {
    &self.coin
}
