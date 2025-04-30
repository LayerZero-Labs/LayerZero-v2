use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SetConfigParams)]
pub struct SetConfig<'info> {
    pub endpoint: Signer<'info>,
    #[account(has_one = endpoint, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    #[account(
        mut,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump = send_config.bump
    )]
    pub send_config: Account<'info, SendConfig>,
    #[account(
        mut,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump = receive_config.bump
    )]
    pub receive_config: Account<'info, ReceiveConfig>,
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = default_send_config.bump
    )]
    pub default_send_config: Account<'info, SendConfig>,
    #[account(
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = default_receive_config.bump
    )]
    pub default_receive_config: Account<'info, ReceiveConfig>,
}

impl SetConfig<'_> {
    pub fn apply(ctx: &mut Context<SetConfig>, params: &SetConfigParams) -> Result<()> {
        let config = Config::deserialize(params.config_type, params.config.as_slice())?;
        match &config {
            Config::Executor(config) => {
                ctx.accounts.send_config.executor.set_config(config)?;
            },
            Config::SendUln(config) => {
                ctx.accounts.send_config.uln.set_config(config)?;

                // get ULN config again as a catch all to ensure the config is valid
                UlnConfig::get_config(
                    &ctx.accounts.default_send_config.uln,
                    &ctx.accounts.send_config.uln,
                )?;
            },
            Config::ReceiveUln(config) => {
                ctx.accounts.receive_config.uln.set_config(config)?;

                // get ULN config again as a catch all to ensure the config is valid
                UlnConfig::get_config(
                    &ctx.accounts.default_receive_config.uln,
                    &ctx.accounts.receive_config.uln,
                )?;
            },
        }
        emit_cpi!(ConfigSetEvent { eid: params.eid, oapp: params.oapp, config: config.clone() });
        Ok(())
    }
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub enum Config {
    SendUln(UlnConfig),
    ReceiveUln(UlnConfig),
    Executor(ExecutorConfig),
}

impl Config {
    pub const EXECUTOR: u32 = 1;
    pub const SEND_ULN: u32 = 2;
    pub const RECEIVE_ULN: u32 = 3;

    pub fn deserialize(config_type: u32, mut config: &[u8]) -> Result<Self> {
        match config_type {
            Self::EXECUTOR => Ok(Self::Executor(ExecutorConfig::deserialize(&mut config)?)),
            Self::SEND_ULN => Ok(Self::SendUln(UlnConfig::deserialize(&mut config)?)),
            Self::RECEIVE_ULN => Ok(Self::ReceiveUln(UlnConfig::deserialize(&mut config)?)),
            _ => Err(UlnError::InvalidConfigType.into()),
        }
    }
}
