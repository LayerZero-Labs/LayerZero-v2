use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 1

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SendParams)]
pub struct Send<'info> {
    pub sender: Signer<'info>,
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, sender.key.as_ref(), &params.dst_eid.to_be_bytes()],
        bump = send_library_config.bump
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.dst_eid.to_be_bytes()],
        bump = default_send_library_config.bump
    )]
    pub default_send_library_config: Account<'info, SendLibraryConfig>,
    /// The PDA signer to the send library when the endpoint calls the send library.
    #[account(
        seeds = [
            MESSAGE_LIB_SEED,
            &get_send_library(
                &send_library_config,
                &default_send_library_config
            ).key().to_bytes()
        ],
        bump = send_library_info.bump,
        constraint = !send_library_info.to_account_info().is_writable @LayerZeroError::ReadOnlyAccount
    )]
    pub send_library_info: Account<'info, MessageLibInfo>,
    #[account(seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        mut,
        seeds = [
            NONCE_SEED,
            &sender.key().to_bytes(),
            &params.dst_eid.to_be_bytes(),
            &params.receiver[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendParams {
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub message: Vec<u8>,
    pub options: Vec<u8>,
    pub native_fee: u64,
    pub lz_token_fee: u64,
}

pub(crate) fn get_send_library(
    config: &SendLibraryConfig,
    default_config: &SendLibraryConfig,
) -> Pubkey {
    if config.message_lib == DEFAULT_MESSAGE_LIB {
        default_config.message_lib
    } else {
        config.message_lib
    }
}
