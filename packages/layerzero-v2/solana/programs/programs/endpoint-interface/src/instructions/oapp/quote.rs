use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 0
/// don't need to separate quote and quote_with_lz_token as it does not process payment on quote()
#[derive(CpiContext, Accounts)]
#[instruction(params: QuoteParams)]
pub struct Quote<'info> {
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.sender.to_bytes(), &params.dst_eid.to_be_bytes()],
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
        seeds = [
            NONCE_SEED,
            &params.sender.to_bytes(),
            &params.dst_eid.to_be_bytes(),
            &params.receiver[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
}

impl Quote<'_> {
    pub fn apply(_ctx: &Context<Quote>, _params: &QuoteParams) -> Result<MessagingFee> {
        Ok(MessagingFee { native_fee: 0, lz_token_fee: 0 })
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteParams {
    pub sender: Pubkey,
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub message: Vec<u8>,
    pub options: Vec<u8>,
    pub pay_in_lz_token: bool,
}
