/// Migration Module
///
/// This module provides functionality for packaging and managing OFT components
/// during migration operations. It defines the data structures and functions
/// needed to safely transfer OFT state between contract versions.
module oft_common::migration;

use call::call_cap::CallCap;
use iota::{bag::Bag, balance::Balance, coin::TreasuryCap};

// === Errors ===

const EEitherTreasuryOrEscrow: u64 = 1;
const EInvalidMigrationCap: u64 = 2;

// === Structs ===

/// Migration capability that authorizes OFT migration operations.
///
/// This capability serves as a security token that must be presented to
/// execute migration functions. It ensures that only authorized parties
/// can perform migration operations on OFT contracts.
public struct MigrationCap has key, store {
    id: UID,
}

/// Container for OFT components during migration operations.
public struct MigrationTicket<phantom T> {
    /// Address of the migration capability
    migration_cap: address,
    /// Call capability granting authorization for LayerZero operations
    oft_cap: CallCap,
    /// Treasury capability for standard OFT (mint/burn model)
    /// Some for standard OFT, None for adapter OFT
    treasury_cap: Option<TreasuryCap<T>>,
    /// Escrow balance for adapter OFT (escrow/release model)
    /// Some for adapter OFT, None for standard OFT
    escrow: Option<Balance<T>>,
    /// Additional data storage for extensibility and future upgrades
    extra: Bag,
}

// === Creation ===

/// Creates a new migration capability.
public fun new_migration_cap(ctx: &mut TxContext): MigrationCap {
    MigrationCap { id: object::new(ctx) }
}

/// Creates a migration ticket from OFT components.
public fun create_migration_ticket<T>(
    migration_cap: &MigrationCap,
    oft_cap: CallCap,
    treasury_cap: Option<TreasuryCap<T>>,
    escrow: Option<Balance<T>>,
    extra: Bag,
): MigrationTicket<T> {
    assert!(
        treasury_cap.is_none() && escrow.is_some() || treasury_cap.is_some() && escrow.is_none(),
        EEitherTreasuryOrEscrow,
    );
    MigrationTicket { migration_cap: object::id_address(migration_cap), oft_cap, treasury_cap, escrow, extra }
}

// === Destruction ===

/// Destroys a migration capability and cleans up its resources.
public fun destroy_migration_cap(self: MigrationCap) {
    let MigrationCap { id } = self;
    object::delete(id);
}

/// Unpacks a migration ticket to retrieve its individual components.
public fun destroy_migration_ticket<T>(
    self: MigrationTicket<T>,
    migration_cap: &MigrationCap,
): (CallCap, Option<TreasuryCap<T>>, Option<Balance<T>>, Bag) {
    assert!(object::id_address(migration_cap) == self.migration_cap, EInvalidMigrationCap);

    let MigrationTicket { migration_cap: _, oft_cap, treasury_cap, escrow, extra } = self;
    (oft_cap, treasury_cap, escrow, extra)
}
