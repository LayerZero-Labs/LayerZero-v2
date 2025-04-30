use crate::*;

#[derive(Accounts)]
pub struct AdminSetConfig<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [EXECUTOR_CONFIG_SEED],
        bump = config.bump,
        constraint = config.admins.contains(admin.key) @ExecutorError::NotAdmin
    )]
    pub config: Account<'info, ExecutorConfig>,
}

impl AdminSetConfig<'_> {
    pub fn apply(ctx: &mut Context<AdminSetConfig>, params: &AdminSetConfigParams) -> Result<()> {
        params.apply(&mut ctx.accounts.config)?;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum AdminSetConfigParams {
    PriceFeed(Pubkey),
    DefaultMultiplierBps(u16),
    DstConfigs(Vec<DstConfig>),
}

impl AdminSetConfigParams {
    pub fn apply(&self, config: &mut ExecutorConfig) -> Result<()> {
        match self {
            AdminSetConfigParams::PriceFeed(price_feed) => {
                config.price_feed = *price_feed;
                Ok(())
            },
            AdminSetConfigParams::DefaultMultiplierBps(default_multiplier_bps) => {
                config.default_multiplier_bps = *default_multiplier_bps;
                Ok(())
            },
            AdminSetConfigParams::DstConfigs(dst_configs) => {
                config.set_dst_configs(dst_configs.clone())
            },
        }
    }
}
