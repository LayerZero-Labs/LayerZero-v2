use crate::*;

#[derive(Accounts)]
#[instruction(params: InitConfigParams)]
pub struct InitConfig<'info> {
    pub endpoint: Signer<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(has_one = endpoint, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    #[account(
        init,
        payer = payer,
        space = 8 + SendConfig::INIT_SPACE,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump
    )]
    pub send_config: Account<'info, SendConfig>,
    #[account(
        init,
        payer = payer,
        space = 8 + ReceiveConfig::INIT_SPACE,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump
    )]
    pub receive_config: Account<'info, ReceiveConfig>,
    pub system_program: Program<'info, System>,
}

impl InitConfig<'_> {
    pub fn apply(ctx: &mut Context<InitConfig>, _params: &InitConfigParams) -> Result<()> {
        ctx.accounts.send_config.bump = ctx.bumps.send_config;
        ctx.accounts.receive_config.bump = ctx.bumps.receive_config;
        Ok(())
    }
}
