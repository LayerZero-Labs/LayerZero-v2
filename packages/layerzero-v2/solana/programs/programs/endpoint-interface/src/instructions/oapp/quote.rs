use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 0
/// don't need to separate quote and quote_with_lz_token as it does not process payment on quote()
#[derive(CpiContext, Accounts)]
#[instruction(params: QuoteParams)]
pub struct Quote<'info> {
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    pub send_library_config: UncheckedAccount<'info>,
    pub default_send_library_config: UncheckedAccount<'info>,
    /// The PDA signer to the send library when the endpoint calls the send library.
    pub send_library_info: UncheckedAccount<'info>,
    pub endpoint: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
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
