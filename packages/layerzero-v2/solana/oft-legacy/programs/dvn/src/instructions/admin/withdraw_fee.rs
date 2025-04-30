use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct WithdrawFee<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [DVN_CONFIG_SEED],
        bump = config.bump,
        constraint = config.admins.contains(admin.key) @DvnError::NotAdmin
    )]
    pub config: Account<'info, DvnConfig>,
    #[account(mut)]
    pub receiver: UncheckedAccount<'info>,
}

impl WithdrawFee<'_> {
    pub fn apply(ctx: &mut Context<WithdrawFee>, params: &WithdrawFeeParams) -> Result<()> {
        let required_lamports = Rent::get()?.minimum_balance(8 + DvnConfig::INIT_SPACE);
        let surplus_lamports = ctx.accounts.config.get_lamports() - required_lamports;
        require!(surplus_lamports >= params.amount, DvnError::InvalidAmount);

        ctx.accounts.config.sub_lamports(params.amount)?;
        ctx.accounts.receiver.add_lamports(params.amount)?;

        emit_cpi!(FeeWithdrawnEvent {
            receiver: ctx.accounts.receiver.key(),
            amount: params.amount,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct WithdrawFeeParams {
    pub amount: u64,
}
