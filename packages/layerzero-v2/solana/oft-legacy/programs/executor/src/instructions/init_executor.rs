use crate::*;

#[derive(Accounts)]
pub struct InitExecutor<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + ExecutorConfig::INIT_SPACE,
        seeds = [EXECUTOR_CONFIG_SEED],
        bump
    )]
    pub config: Account<'info, ExecutorConfig>,
    pub system_program: Program<'info, System>,
}

impl InitExecutor<'_> {
    pub fn apply(ctx: &mut Context<InitExecutor>, params: &InitExecutorParams) -> Result<()> {
        ctx.accounts.config.bump = ctx.bumps.config;
        ctx.accounts.config.owner = params.owner;
        ctx.accounts.config.set_admins(params.admins.clone())?;
        ctx.accounts.config.set_msglibs(params.msglibs.clone())?;
        ctx.accounts.config.price_feed = params.price_feed;
        ctx.accounts.config.default_multiplier_bps = 12000; // 1.2x
        ctx.accounts.config.paused = false;
        ctx.accounts.config.set_executors(params.executors.clone())?;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitExecutorParams {
    pub owner: Pubkey,
    pub admins: Vec<Pubkey>,
    pub executors: Vec<Pubkey>,
    pub msglibs: Vec<Pubkey>,
    pub price_feed: Pubkey,
}
