use std::collections::HashMap;

use anchor_lang::prelude::*;
use anchor_lang::solana_program::address_lookup_table::state::AddressLookupTable;
use anchor_lang::Discriminator;

pub const EXECUTION_CONTEXT_SEED: &[u8] = b"ExecutionContext";
pub const EXECUTION_CONTEXT_VERSION_1: u8 = 1;

/// Execution context data structure that contains metadata for cross-chain execution
/// This provides execution limits and tracking for LayerZero operations
#[derive(InitSpace, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct ExecutionContextV1 {
    pub initial_payer_balance: u64,
    /// The maximum total lamports allowed to be used by all instructions in this execution.
    /// This is a hard cap for the sum of lamports consumed by all instructions in the execution
    /// batch.
    pub fee_limit: u64,
}

impl anchor_lang::Discriminator for ExecutionContextV1 {
    // let discriminator_preimage = "account:ExecutionContextV1";
    // let hash = anchor_lang::solana_program::hash::hash(discriminator_preimage.as_bytes());
    const DISCRIMINATOR: &'static [u8] = &[132, 92, 176, 59, 141, 186, 141, 137];
}

impl anchor_lang::AccountDeserialize for ExecutionContextV1 {
    fn try_deserialize(buf: &mut &[u8]) -> anchor_lang::Result<Self> {
        if buf.len() < Self::DISCRIMINATOR.len() {
            return Err(anchor_lang::error::ErrorCode::AccountDiscriminatorNotFound.into());
        }
        let given_disc = &buf[..8];
        if Self::DISCRIMINATOR != given_disc {
            return Err(anchor_lang::error!(
                anchor_lang::error::ErrorCode::AccountDiscriminatorMismatch
            )
            .with_account_name("ExecutionContextV1"));
        }
        Self::try_deserialize_unchecked(buf)
    }

    fn try_deserialize_unchecked(buf: &mut &[u8]) -> anchor_lang::Result<Self> {
        let mut data: &[u8] = &buf[8..];
        anchor_lang::AnchorDeserialize::deserialize(&mut data)
            .map_err(|_| anchor_lang::error::ErrorCode::AccountDidNotDeserialize.into())
    }
}

/// A generic account locator used in LZ execution planning for V2.
/// Can reference the address directly, via ALT, or as a placeholder.
///
/// This enum enables the compact account referencing design of V2, supporting:
/// - OApps to request multiple signer accounts, not just a single Executor EOA
/// - Dynamic creation of writable EOA-based data accounts
/// - Efficient encoding of addresses via ALTs, reducing account list size
///
/// The legacy is_signer flag is removed. Instead, signer roles are explicitly
/// declared through Payer and indexed Signer(u8) variants.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub enum AddressLocator {
    /// Directly supplied public key - standard address reference
    Address(Pubkey),
    /// Indexed address from a specific Address Lookup Table (ALT)
    /// Format: (ALT list index, address index within ALT)
    /// Enables efficient account list compression via Solana's ALT mechanism
    AltIndex(u8, u8),
    /// Executor's fee payer - substituted by the Executor's EOA
    /// This is the primary signer and fee payer for the transaction
    Payer,
    /// Additional signer accounts - substituted by EOAs provided by the Executor
    /// The u8 index identifies each signer's position in the signer list,
    /// allowing the OApp to reference multiple distinct signers for dynamic account creation
    Signer(u8),
    /// A context account provided by the Executor containing execution
    /// metadata, such as SOL spend limits.
    Context,
    // Append more address placeholders in the future.
}

impl From<Pubkey> for AddressLocator {
    fn from(pubkey: Pubkey) -> Self {
        AddressLocator::Address(pubkey)
    }
}

/// Account metadata for V2 execution planning.
/// Used by the Executor to construct the final transaction.
///
/// V2 removes the legacy is_signer flag from V1's AccountMeta.
/// Instead, signer roles are explicitly declared through AddressLocator variants.
/// This provides clearer semantics and enables multiple signer support.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct AccountMetaRef {
    /// The account address locator - supports multiple resolution strategies
    pub pubkey: AddressLocator,
    /// Whether the account should be writable in the final transaction
    pub is_writable: bool,
}

pub fn compact_accounts_with_alts(
    alt_accounts: &[AccountInfo],
    instruction_accounts: Vec<AccountMetaRef>,
) -> Result<Vec<AccountMetaRef>> {
    // Build address lookup table mapping from remaining_accounts
    // This enables efficient account referencing via ALT indices
    let address_to_alt_index_map = build_address_to_alt_index_map(alt_accounts)?;

    // Convert accounts to use ALT indices where possible
    let compacted_accounts = instruction_accounts
        .into_iter()
        .map(|mut account_meta| {
            if let AddressLocator::Address(pubkey) = account_meta.pubkey {
                account_meta.pubkey = to_address_locator(&address_to_alt_index_map, pubkey);
            }
            account_meta
        })
        .collect();

    Ok(compacted_accounts)
}

pub fn to_address_locator(
    address_to_alt_index_map: &HashMap<Pubkey, (u8, u8)>,
    key: Pubkey,
) -> AddressLocator {
    address_to_alt_index_map
        .get(&key)
        .map(|alt_index| AddressLocator::AltIndex(alt_index.0, alt_index.1))
        .unwrap_or(AddressLocator::Address(key))
}

/// Helper function to deserialize AddressLookupTable data
pub fn deserialize_alt(alt: &AccountInfo) -> Result<Vec<Pubkey>> {
    AddressLookupTable::deserialize(*alt.try_borrow_data().unwrap())
        .map(|alt| alt.addresses.to_vec())
        .map_err(|_e| error!(crate::ErrorCode::InvalidAddressLookupTable))
}

/// Helper function to build a map of addresses to their ALT indices
pub fn build_address_to_alt_index_map(
    alt_accounts: &[AccountInfo],
) -> Result<HashMap<Pubkey, (u8, u8)>> {
    let mut address_to_alt_index_map: HashMap<Pubkey, (u8, u8)> = HashMap::new();
    for (alt_index, alt) in alt_accounts.iter().enumerate() {
        let addresses_in_alt = deserialize_alt(alt)?;
        for (address_index_in_alt, address_in_alt) in addresses_in_alt.iter().enumerate() {
            address_to_alt_index_map
                .insert(*address_in_alt, (alt_index as u8, address_index_in_alt as u8));
        }
    }
    Ok(address_to_alt_index_map)
}
