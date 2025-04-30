use crate::*;

#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        has_one = admin,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
    #[account(mut)]
    pub receiver: UncheckedAccount<'info>,
}

impl WithdrawFees<'_> {
    pub fn apply(ctx: &mut Context<WithdrawFees>, params: &WithdrawFeesParams) -> Result<()> {
        let required_lamports = Rent::get()?.minimum_balance(8 + MessageLib::INIT_SPACE);
        let surplus_lamports = ctx.accounts.message_lib.get_lamports() - required_lamports;

        if surplus_lamports >= params.amount {
            ctx.accounts.message_lib.sub_lamports(params.amount)?;
            ctx.accounts.receiver.add_lamports(params.amount)?;

            Ok(())
        } else {
            Err(SimpleMessageLibError::InvalidAmount.into())
        }
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct WithdrawFeesParams {
    pub amount: u64,
}
