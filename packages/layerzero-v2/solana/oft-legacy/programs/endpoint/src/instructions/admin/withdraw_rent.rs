use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct WithdrawRent<'info> {
    pub admin: Signer<'info>,
    #[account(mut, has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>, // this account collects the rent from the cleared payloadHashes.
    #[account(mut)]
    pub receiver: UncheckedAccount<'info>,
}

impl WithdrawRent<'_> {
    pub fn apply(ctx: &mut Context<WithdrawRent>, params: &WithdrawRentParams) -> Result<()> {
        let required_lamports = Rent::get()?.minimum_balance(8 + EndpointSettings::INIT_SPACE);
        let surplus_lamports = ctx.accounts.endpoint.get_lamports() - required_lamports;
        require!(surplus_lamports >= params.amount, LayerZeroError::InvalidAmount);

        ctx.accounts.endpoint.sub_lamports(params.amount)?;
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
