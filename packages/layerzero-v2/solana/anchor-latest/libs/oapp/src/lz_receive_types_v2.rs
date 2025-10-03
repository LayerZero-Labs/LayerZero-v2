use crate::common::{AccountMetaRef, AddressLocator};
use crate::endpoint_cpi::EVENT_SEED;
use anchor_lang::{
    prelude::*,
    solana_program::{keccak::hash, system_program::ID as SYSTEM_ID},
};
use endpoint_interface::{
    COMPOSED_MESSAGE_HASH_SEED, ENDPOINT_SEED, NONCE_SEED, OAPP_SEED, PAYLOAD_HASH_SEED,
};

pub const LZ_RECEIVE_TYPES_VERSION: u8 = 2;

/// Return payload of `lz_receive_types_info` (version == 2).
/// Used by the Executor to construct the call to `lz_receive_types_v2`.
///
/// `lz_receive_types_info` accounts:
/// 1. `oapp_account`: the OApp identity/account.
/// 2. `lz_receive_types_accounts`: PDA derived with `seeds = [LZ_RECEIVE_TYPES_SEED,
///    &oapp_account.key().to_bytes()]`.
/// The program reads this PDA to compute and return `LzReceiveTypesV2Accounts`.
///
/// Execution flow:
/// 1. Version discovery: call `lz_receive_types_info`; when version is 2, decode into
///    `LzReceiveTypesV2Accounts`.
/// 2. Execution planning: build the account metas for `lz_receive_types_v2` from the decoded value;
///    calling `lz_receive_types_v2` returns the complete execution plan.
///
/// Fields:
/// - `accounts`: `Pubkey`s returned by `lz_receive_types_info`.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LzReceiveTypesV2Accounts {
    pub accounts: Vec<Pubkey>,
}

/// Output of the lz_receive_types_v2 instruction.
///
/// This structure enables the multi-instruction execution model where OApps can
/// define multiple instructions to be executed atomically by the Executor.
/// The Executor constructs a single transaction containing all returned instructions.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LzReceiveTypesV2Result {
    /// The version of context account
    pub context_version: u8,
    /// ALTs required for this execution context
    /// Used by the Executor to resolve AltIndex references in AccountMetaRef
    /// Enables efficient account list compression for complex transactions
    pub alts: Vec<Pubkey>,
    /// The complete list of instructions required for LzReceive execution
    /// MUST include exactly one LzReceive instruction
    /// MAY include additional Standard instructions for preprocessing/postprocessing
    /// Instructions are executed in the order returned
    pub instructions: Vec<Instruction>,
}

/// The list of instructions that can be executed in the LzReceive transaction.
///
/// V2's multi-instruction model enables complex patterns such as:
/// - Preprocessing steps before lz_receive (e.g., account initialization)
/// - Postprocessing steps after lz_receive (e.g., verification, cleanup)
/// - ABA messaging patterns with additional LayerZero sends
/// - Conditional execution flows based on message content
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub enum Instruction {
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
        program_id: Pubkey,
        /// Account list for the custom instruction
        /// Uses same AddressLocator system as LzReceive
        accounts: Vec<AccountMetaRef>,
        /// Instruction data payload
        /// Raw bytes containing the instruction's parameters
        data: Vec<u8>,
    },
}

/// V2 version of get_accounts_for_clear that returns AccountMetaRef
pub fn get_accounts_for_clear(
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
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
        AccountMetaRef { pubkey: (*receiver).into(), is_writable: false },
        AccountMetaRef { pubkey: oapp_registry_account.into(), is_writable: false },
        AccountMetaRef { pubkey: nonce_account.into(), is_writable: false },
        AccountMetaRef { pubkey: payload_hash_account.into(), is_writable: true },
        AccountMetaRef { pubkey: endpoint_settings_account.into(), is_writable: true },
        AccountMetaRef { pubkey: event_authority_account.into(), is_writable: false },
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
    ]
}

/// V2 version of get_accounts_for_send_compose that returns AccountMetaRef
pub fn get_accounts_for_send_compose(
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
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
        AccountMetaRef { pubkey: (*from).into(), is_writable: false },
        AccountMetaRef { pubkey: AddressLocator::Payer, is_writable: true },
        AccountMetaRef { pubkey: composed_message_account.into(), is_writable: true },
        AccountMetaRef { pubkey: SYSTEM_ID.into(), is_writable: false },
        AccountMetaRef { pubkey: event_authority_account.into(), is_writable: false },
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
    ]
}

/// V2 version of get_accounts_for_clear_compose that returns AccountMetaRef
pub fn get_accounts_for_clear_compose(
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
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
        AccountMetaRef { pubkey: (*to).into(), is_writable: false },
        AccountMetaRef { pubkey: composed_message_account.into(), is_writable: true },
        AccountMetaRef { pubkey: event_authority_account.into(), is_writable: false },
        AccountMetaRef { pubkey: endpoint_program.into(), is_writable: false },
    ]
}
