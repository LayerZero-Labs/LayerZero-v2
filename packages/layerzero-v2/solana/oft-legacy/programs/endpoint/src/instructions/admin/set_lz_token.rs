use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct SetLzToken<'info> {
    pub admin: Signer<'info>,
    #[account(mut, has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
}

impl SetLzToken<'_> {
    pub fn apply(ctx: &mut Context<SetLzToken>, params: &SetLzTokenParams) -> Result<()> {
        ctx.accounts.endpoint.lz_token_mint = params.lz_token;
        emit_cpi!(LzTokenSetEvent { token: params.lz_token });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetLzTokenParams {
    pub lz_token: Option<Pubkey>,
}
