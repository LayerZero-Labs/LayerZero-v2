use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct WithdrawRent<'info> {
    pub admin: Signer<'info>,
    #[account(mut, has_one = admin, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    #[account(mut)]
    pub receiver: UncheckedAccount<'info>,
}

impl WithdrawRent<'_> {
    pub fn apply(ctx: &mut Context<WithdrawRent>, params: &WithdrawRentParams) -> Result<()> {
        let required_lamports = Rent::get()?.minimum_balance(8 + UlnSettings::INIT_SPACE);
        let surplus_lamports = ctx.accounts.uln.get_lamports() - required_lamports;
        require!(params.amount <= surplus_lamports, UlnError::InvalidAmount);

        ctx.accounts.uln.sub_lamports(params.amount)?;
        ctx.accounts.receiver.add_lamports(params.amount)?;

        emit_cpi!(RentWithdrawnEvent {
            receiver: ctx.accounts.receiver.key(),
            amount: params.amount,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct WithdrawRentParams {
    pub amount: u64,
}
