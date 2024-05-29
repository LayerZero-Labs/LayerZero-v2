use crate::*;

#[derive(Accounts)]
pub struct InitUln<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + UlnSettings::INIT_SPACE,
        seeds = [ULN_SEED],
        bump
    )]
    pub uln: Account<'info, UlnSettings>,
    pub system_program: Program<'info, System>,
}

impl InitUln<'_> {
    pub fn apply(ctx: &mut Context<InitUln>, params: &InitUlnParams) -> Result<()> {
        ctx.accounts.uln.eid = params.eid;
        ctx.accounts.uln.endpoint = params.endpoint;
        ctx.accounts.uln.endpoint_program = params.endpoint_program;
        ctx.accounts.uln.admin = params.admin;
        ctx.accounts.uln.treasury = None;
        ctx.accounts.uln.bump = ctx.bumps.uln;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitUlnParams {
    pub eid: u32,
    pub endpoint: Pubkey, // the PDA signer of the endpoint program
    pub endpoint_program: Pubkey,
    pub admin: Pubkey,
}
