use crate::{endpoint_cpi::EVENT_SEED, AltIndex};
use anchor_lang::{
    prelude::*,
    solana_program::{
        address_lookup_table::state::AddressLookupTable, keccak::hash,
        system_program::ID as SYSTEM_ID,
    },
};
use endpoint::{
    COMPOSED_MESSAGE_HASH_SEED, ENDPOINT_SEED, NONCE_SEED, OAPP_SEED, PAYLOAD_HASH_SEED,
};
use std::collections::HashMap;

/// Output of the lz_receive_types_v2 instruction.
///
/// This structure enables the multi-instruction execution model where OApps can
/// define multiple instructions to be executed atomically by the Executor.
/// The Executor constructs a single transaction containing all returned instructions.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LzReceiveTypesV2Result {
    /// ALTs required for this execution context (can be empty if no ALTs are needed)
    /// Used by the Executor to resolve AltIndex references in AccountMetaRef
    /// Enables efficient account list compression for complex transactions
    pub alts: Vec<Pubkey>,
    /// The complete list of instructions required for LzReceive execution
    /// MUST include exactly one LzReceive instruction
    /// MAY include additional Standard instructions for preprocessing/postprocessing
    /// Instructions are executed in the order returned
    pub instructions: Vec<LzInstruction>,
}

/// The list of instructions that can be executed in the LzReceive transaction.
///
/// V2's multi-instruction model enables complex patterns such as:
/// - Preprocessing steps before lz_receive (e.g., account initialization)
/// - Postprocessing steps after lz_receive (e.g., verification, cleanup)
/// - ABA messaging patterns with additional LayerZero sends
/// - Conditional execution flows based on message content
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub enum LzInstruction {
    /// The main LzReceive instruction (exactly one required per transaction)
    /// This instruction processes the incoming cross-chain message
    LzReceive {
        /// Account list for the lz_receive instruction
        /// Uses AddressLocator for flexible address resolution
        accounts: Vec<AccountMetaRef>,
    },
    /// Arbitrary custom instruction for preprocessing/postprocessing
    /// Enables OApps to implement complex execution flows
    Standard {
        /// Target program ID for the custom instruction
        /// Can reference direct address or ALT index
        program_id: AddressLocator,
        /// Account list for the custom instruction
        /// Uses same AddressLocator system as LzReceive
        accounts: Vec<AccountMetaRef>,
        /// Instruction data payload
        /// Raw bytes containing the instruction's parameters
        data: Vec<u8>,
    },
}

/// Helper function to compute Anchor instruction discriminator
/// Used for constructing Standard instruction data payloads
pub fn instruction_discriminator(name: &str) -> [u8; 8] {
    let preimage = format!("global:{}", name);
    let preimage_bytes = preimage.as_bytes();
    let hash = anchor_lang::solana_program::hash::hash(preimage_bytes);
    let mut discriminator = [0u8; 8];
    discriminator.copy_from_slice(&hash.to_bytes()[..8]);
    discriminator
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
    /// Executor's fee payer - substituted by the Executor's EOA
    /// This is the primary signer and fee payer for the transaction
    Payer,
    /// Additional signer accounts - substituted by EOAs provided by the Executor
    /// The u8 index identifies each signer's position in the signer list,
    /// allowing the OApp to reference multiple distinct signers for dynamic account creation
    Signer(u8),
    /// Directly supplied public key - standard address reference
    Address(Pubkey),
    /// Indexed address from a specific Address Lookup Table (ALT)
    /// Format: (ALT list index, address index within ALT)
    /// Enables efficient account list compression via Solana's ALT mechanism
    AltIndex(u8, u8),
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

/// V2 version of get_accounts_for_clear that returns AccountMetaRef
pub fn get_accounts_for_clear(
    alts_addresses: &HashMap<Pubkey, AltIndex>,
    endpoint_program: Pubkey,
    receiver: &Pubkey,
    src_eid: u32,
    sender: &[u8; 32],
    nonce: u64,
) -> Vec<AccountMetaRef> {
    let (nonce_account, _) = Pubkey::find_program_address(
        &[NONCE_SEED, &receiver.to_bytes(), &src_eid.to_be_bytes(), sender],
        &endpoint_program,
    );

    let (payload_hash_account, _) = Pubkey::find_program_address(
        &[
            PAYLOAD_HASH_SEED,
            &receiver.to_bytes(),
            &src_eid.to_be_bytes(),
            sender,
            &nonce.to_be_bytes(),
        ],
        &endpoint_program,
    );

    let (oapp_registry_account, _) =
        Pubkey::find_program_address(&[OAPP_SEED, &receiver.to_bytes()], &endpoint_program);
    let (event_authority_account, _) =
        Pubkey::find_program_address(&[EVENT_SEED], &endpoint_program);
    let (endpoint_settings_account, _) =
        Pubkey::find_program_address(&[ENDPOINT_SEED], &endpoint_program);

    vec![
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, *receiver),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, oapp_registry_account),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, nonce_account),
            is_writable: true,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, payload_hash_account),
            is_writable: true,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_settings_account),
            is_writable: true,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, event_authority_account),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
    ]
}

/// V2 version of get_accounts_for_send_compose that returns AccountMetaRef
pub fn get_accounts_for_send_compose(
    alts_addresses: &HashMap<Pubkey, AltIndex>,
    endpoint_program: Pubkey,
    from: &Pubkey,
    to: &Pubkey,
    guid: &[u8; 32],
    index: u16,
    composed_message: &[u8],
) -> Vec<AccountMetaRef> {
    let (composed_message_account, _) = Pubkey::find_program_address(
        &[
            COMPOSED_MESSAGE_HASH_SEED,
            &from.to_bytes(),
            &to.to_bytes(),
            &guid[..],
            &index.to_be_bytes(),
            &hash(composed_message).to_bytes(),
        ],
        &endpoint_program,
    );

    let (event_authority_account, _) =
        Pubkey::find_program_address(&[EVENT_SEED], &endpoint_program);

    vec![
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
        AccountMetaRef { pubkey: to_address_locator(alts_addresses, *from), is_writable: false },
        AccountMetaRef { pubkey: AddressLocator::Payer, is_writable: true },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, composed_message_account),
            is_writable: true,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, SYSTEM_ID),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, event_authority_account),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
    ]
}

/// V2 version of get_accounts_for_clear_compose that returns AccountMetaRef
pub fn get_accounts_for_clear_compose(
    alts_addresses: &HashMap<Pubkey, AltIndex>,
    endpoint_program: Pubkey,
    from: &Pubkey,
    to: &Pubkey,
    guid: &[u8; 32],
    index: u16,
    composed_message: &[u8],
) -> Vec<AccountMetaRef> {
    let (composed_message_account, _) = Pubkey::find_program_address(
        &[
            COMPOSED_MESSAGE_HASH_SEED,
            &from.to_bytes(),
            &to.to_bytes(),
            &guid[..],
            &index.to_be_bytes(),
            &hash(composed_message).to_bytes(),
        ],
        &endpoint_program,
    );

    let (event_authority_account, _) =
        Pubkey::find_program_address(&[EVENT_SEED], &endpoint_program);

    vec![
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
        AccountMetaRef { pubkey: to_address_locator(alts_addresses, *to), is_writable: false },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, composed_message_account),
            is_writable: true,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, event_authority_account),
            is_writable: false,
        },
        AccountMetaRef {
            pubkey: to_address_locator(alts_addresses, endpoint_program),
            is_writable: false,
        },
    ]
}

pub fn to_address_locator(
    alts_addresses: &HashMap<Pubkey, AltIndex>,
    key: Pubkey,
) -> AddressLocator {
    if let Some(alt_index) = alts_addresses.get(&key) {
        return AddressLocator::AltIndex(alt_index.0, alt_index.1);
    }
    AddressLocator::Address(key)
}

/// Helper function to deserialize AddressLookupTable data
pub fn deserialize_alt(alt: &AccountInfo) -> Result<Vec<Pubkey>> {
    AddressLookupTable::deserialize(*alt.try_borrow_data().unwrap())
        .map(|alt| alt.addresses.to_vec())
        .map_err(|_e| error!(crate::ErrorCode::InvalidAddressLookupTable))
}

/// Helper function to build a map of addresses to their ALT indices
pub fn build_alt_address_map(accounts: &[AccountInfo]) -> Result<HashMap<Pubkey, AltIndex>> {
    let mut alt_address_map: HashMap<Pubkey, (u8, u8)> = HashMap::new();
    for (i, alt) in accounts.iter().enumerate() {
        let alt_addresses = deserialize_alt(alt)?;
        for (idx_within_alt, alt_address) in alt_addresses.iter().enumerate() {
            alt_address_map.insert(*alt_address, (i as u8, idx_within_alt as u8));
        }
    }
    Ok(alt_address_map)
}
