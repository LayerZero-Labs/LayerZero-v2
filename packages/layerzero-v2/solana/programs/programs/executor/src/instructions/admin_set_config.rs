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
        let account_size = ctx.accounts.config.to_account_info().data_len();
        // let init_space = ExecutorConfig::INIT_SPACE;
        // let max_len = (account_size - init_space) / DstConfig::INIT_SPACE + DST_CONFIG_DEFAULT_LEN;
        let max_len = if account_size > (ExecutorConfig::INIT_SPACE + 8) {
            DST_CONFIG_MAX_LEN
        } else {
            DST_CONFIG_DEFAULT_LEN
        };
        params.apply(max_len, &mut ctx.accounts.config)?;
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
    pub fn apply(&self, dst_configs_max_len: usize, config: &mut ExecutorConfig) -> Result<()> {
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
                config.set_dst_configs(dst_configs_max_len, dst_configs.clone())
            },
        }
    }
}
