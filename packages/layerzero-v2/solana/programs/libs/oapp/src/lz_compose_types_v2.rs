use crate::{common::AccountMetaRef, endpoint_cpi::EVENT_SEED};
use anchor_lang::{prelude::*, solana_program::keccak::hash};
use endpoint::COMPOSED_MESSAGE_HASH_SEED;

pub const LZ_COMPOSE_TYPES_VERSION: u8 = 2;

/// Return payload of `lz_compose_types_info` (version == 2).
/// Used by the Executor to construct the call to `lz_compose_types_v2`.
///
/// `lz_compose_types_info` accounts:
/// 1. `composer_account`: the Composer identity/account.
/// 2. `lz_compose_types_accounts`: PDA derived with `seeds = [LZ_COMPOSE_TYPES_SEED,
///    &composer_account.key().to_bytes()]`.
/// The program reads this PDA to compute and return `LzComposeTypesV2Accounts`.
///
/// Execution flow:
/// 1. Version discovery: call `lz_compose_types_info`; when version is 2, decode into
///    `LzComposeTypesV2Accounts`.
/// 2. Execution planning: build the account metas for `lz_compose_types_v2` from the decoded value;
///    calling `lz_compose_types_v2` returns the complete execution plan.
///
/// Fields:
/// - `accounts`: `Pubkey`s returned by `lz_compose_types_info`.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LzComposeTypesV2Accounts {
    pub accounts: Vec<Pubkey>,
}

/// Output of the lz_compose_types_v2 instruction.
///
/// This structure enables the multi-instruction execution model where Composer can
/// define multiple instructions to be executed atomically by the Executor.
/// The Executor constructs a single transaction containing all returned instructions.
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LzComposeTypesV2Result {
    /// The version of context account
    pub context_version: u8,
    /// ALTs required for this execution context
    /// Used by the Executor to resolve AltIndex references in AccountMetaRef
    /// Enables efficient account list compression for complex transactions
    pub alts: Vec<Pubkey>,
    /// The complete list of instructions required for LzCompose execution
    /// MUST include exactly one LzCompose instruction
    /// MAY include additional Standard instructions for preprocessing/postprocessing
    /// Instructions are executed in the order returned
    pub instructions: Vec<Instruction>,
}

/// The list of instructions that can be executed in the LzCompose transaction.
///
/// V2's multi-instruction model enables complex patterns such as:
/// - Preprocessing steps before lz_compose (e.g., account initialization)
/// - Postprocessing steps after lz_compose (e.g., verification, cleanup)
/// - ABA messaging patterns with additional LayerZero sends
/// - Conditional execution flows based on message content
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub enum Instruction {
    /// The main LzCompose instruction (exactly one required per transaction)
    /// This instruction composes the outgoing cross-chain message
    LzCompose {
        /// Account list for the lz_compose instruction
        /// Uses AddressLocator for flexible address resolution
        accounts: Vec<AccountMetaRef>,
    },
    /// Arbitrary custom instruction for preprocessing/postprocessing
    /// Enables Composer to implement complex execution flows
    Standard {
        /// Target program ID for the custom instruction        
        program_id: Pubkey,
        /// Account list for the custom instruction
        /// Uses same AddressLocator system as LzCompose
        accounts: Vec<AccountMetaRef>,
        /// Instruction data payload
        /// Raw bytes containing the instruction's parameters
        data: Vec<u8>,
    },
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
