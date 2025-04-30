use crate::*;

#[derive(Accounts)]
pub struct Quote<'info> {
    /// The message lib authority of the endpoint
    pub endpoint: Signer<'info>,
    #[account(
        seeds = [MESSAGE_LIB_SEED],
        has_one = endpoint,
        bump = message_lib.bump,
    )]
    pub message_lib: Account<'info, MessageLib>,
}

impl Quote<'_> {
    pub fn apply(ctx: &Context<Quote>, params: &QuoteParams) -> Result<MessagingFee> {
        let lz_token_fee =
            if params.pay_in_lz_token { ctx.accounts.message_lib.lz_token_fee } else { 0 };
        Ok(MessagingFee { native_fee: ctx.accounts.message_lib.fee, lz_token_fee })
    }
}
