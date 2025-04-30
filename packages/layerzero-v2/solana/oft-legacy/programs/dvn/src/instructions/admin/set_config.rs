use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct SetConfig<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [DVN_CONFIG_SEED],
        bump = config.bump,
        constraint = config.admins.contains(admin.key) @DvnError::NotAdmin
    )]
    pub config: Account<'info, DvnConfig>,
}

impl SetConfig<'_> {
    pub fn apply(ctx: &mut Context<SetConfig>, params: &SetConfigParams) -> Result<()> {
        let account_size = ctx.accounts.config.to_account_info().data_len();
        let dst_configs_max_len = if account_size > (DvnConfig::INIT_SPACE + 8) {
            DST_CONFIG_MAX_LEN
        } else {
            DST_CONFIG_DEFAULT_LEN
        };
        params.config.apply(dst_configs_max_len, &mut ctx.accounts.config)?;
        emit_cpi!(AdminConfigSetEvent { config: params.config.clone() });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetConfigParams {
    pub config: AdminConfig,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum AdminConfig {
    Admins(Vec<Pubkey>),
    DefaultMultiplierBps(u16),
    DstConfigs(Vec<DstConfig>),
    PriceFeed(Pubkey),
    RemoveDstConfigs(Vec<u32>),
}

impl AdminConfig {
    pub fn apply(&self, dst_configs_max_len: usize, config: &mut DvnConfig) -> Result<()> {
        match self {
            AdminConfig::Admins(admins) => {
                config.set_admins(admins.clone())?;
            },
            AdminConfig::DefaultMultiplierBps(default_multiplier_bps) => {
                config.default_multiplier_bps = *default_multiplier_bps;
            },
            AdminConfig::DstConfigs(dst_configs) => {
                config.set_dst_configs(dst_configs_max_len, dst_configs.clone())?;
            },
            AdminConfig::PriceFeed(price_feed) => {
                config.price_feed = *price_feed;
            },
            AdminConfig::RemoveDstConfigs(dst_eids) => {
                config.remove_dst_configs(dst_eids.clone())?;
            },
        }
        Ok(())
    }
}
