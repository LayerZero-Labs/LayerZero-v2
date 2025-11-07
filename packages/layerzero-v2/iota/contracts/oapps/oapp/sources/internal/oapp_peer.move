/// OApp Peer Management Module
///
/// This module provides functionality for managing cross-chain peer relationships
/// in LayerZero OApps (Omnichain Applications). It allows OApps to register and
/// manage trusted peer contracts on different blockchains.
module oapp::oapp_peer;

use iota::{event, table::{Self, Table}};
use utils::{bytes32::Bytes32, table_ext};

// === Errors ===

const EPeerNotFound: u64 = 0;
const EInvalidPeer: u64 = 1;

// === Structs ===

/// Manages peer relationships for cross-chain communication.
///
/// This struct maintains a mapping of Endpoint IDs (EIDs) to their corresponding
/// peer contract addresses, enabling secure cross-chain message routing and validation.
public struct Peer has store {
    peers: Table<u32, Bytes32>,
}

// === Events ===

/// Event emitted when a peer is set or updated for a specific endpoint.

public struct PeerSetEvent has copy, drop {
    /// Address of the OApp package
    oapp: address,
    /// Endpoint ID of the remote blockchain
    eid: u32,
    /// Address of the peer contract on the remote blockchain
    peer: Bytes32,
}

// === Package Functions ===

/// Creates a new empty Peer registry.
public(package) fun new(ctx: &mut TxContext): Peer {
    Peer { peers: table::new(ctx) }
}

/// Sets or updates a peer address for a specific endpoint.
///
/// This function establishes a trusted relationship with a peer contract
/// on the specified chain. The peer address cannot be zero.
///
/// Parameters:
/// - `self`: Reference to the Peer registry
/// - `oapp`: The address of the OApp package
/// - `eid`: The Endpoint ID of the target blockchain
/// - `peer`: The 32-byte address of the peer contract (must be non-zero)
///
/// Aborts:
/// - `EInvalidPeer`: If the peer address is zero (invalid)
public(package) fun set_peer(self: &mut Peer, oapp: address, eid: u32, peer: Bytes32) {
    assert!(!peer.is_zero(), EInvalidPeer);
    table_ext::upsert!(&mut self.peers, eid, peer);
    event::emit(PeerSetEvent { oapp, eid, peer });
}

// === View Functions ===

/// Checks if a peer is registered for the specified endpoint.
///
/// Parameters:
/// - `self`: Reference to the Peer registry
/// - `eid`: The Endpoint ID to check
///
/// Returns:
/// `true` if a peer is registered for the given EID, `false` otherwise
public(package) fun has_peer(self: &Peer, eid: u32): bool {
    self.peers.contains(eid)
}

/// Retrieves the peer address for a specific chain.
///
/// Parameters:
/// - `self`: Reference to the Peer registry
/// - `eid`: The Endpoint ID
///
/// Returns:
/// The 32-byte address of the peer contract on the specified endpoint
///
/// Aborts:
/// - `EPeerNotFound`: If no peer is registered for the given EID
public(package) fun get_peer(self: &Peer, eid: u32): Bytes32 {
    *table_ext::borrow_or_abort!(&self.peers, eid, EPeerNotFound)
}
