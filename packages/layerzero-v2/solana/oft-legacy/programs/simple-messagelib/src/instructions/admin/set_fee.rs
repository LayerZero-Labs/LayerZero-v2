use crate::*;

#[derive(Accounts)]
pub struct SetFee<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        has_one = admin,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
}

impl SetFee<'_> {
    pub fn apply(ctx: &mut Context<SetFee>, params: &SetFeeParams) -> Result<()> {
        ctx.accounts.message_lib.fee = params.fee;
        ctx.accounts.message_lib.lz_token_fee = params.lz_token_fee;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetFeeParams {
    pub fee: u64,
    pub lz_token_fee: u64,
}
