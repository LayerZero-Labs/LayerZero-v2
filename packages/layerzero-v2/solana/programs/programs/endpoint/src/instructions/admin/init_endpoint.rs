use crate::*;

#[derive(Accounts)]
pub struct InitEndpoint<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + EndpointSettings::INIT_SPACE,
        seeds = [ENDPOINT_SEED],
        bump
    )]
    pub endpoint: Account<'info, EndpointSettings>,
    pub system_program: Program<'info, System>,
}

impl InitEndpoint<'_> {
    pub fn apply(ctx: &mut Context<InitEndpoint>, params: &InitEndpointParams) -> Result<()> {
        // init endpoint settings
        ctx.accounts.endpoint.eid = params.eid;
        ctx.accounts.endpoint.admin = params.admin;
        ctx.accounts.endpoint.bump = ctx.bumps.endpoint;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitEndpointParams {
    pub eid: u32,
    pub admin: Pubkey,
}
