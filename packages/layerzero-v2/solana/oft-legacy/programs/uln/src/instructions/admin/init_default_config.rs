use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: InitDefaultConfigParams)]
pub struct InitDefaultConfig<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    #[account(
        init,
        payer = admin,
        space = 8 + SendConfig::INIT_SPACE,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub send_config: Account<'info, SendConfig>,
    #[account(
        init,
        payer = admin,
        space = 8 + ReceiveConfig::INIT_SPACE,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub receive_config: Account<'info, ReceiveConfig>,
    pub system_program: Program<'info, System>,
}

impl InitDefaultConfig<'_> {
    pub fn apply(
        ctx: &mut Context<InitDefaultConfig>,
        params: &InitDefaultConfigParams,
    ) -> Result<()> {
        ctx.accounts.send_config.uln.set_default_config(&params.send_uln_config)?;
        ctx.accounts.receive_config.uln.set_default_config(&params.receive_uln_config)?;
        ctx.accounts.send_config.executor.set_default_config(&params.executor_config)?;

        ctx.accounts.send_config.bump = ctx.bumps.send_config;
        ctx.accounts.receive_config.bump = ctx.bumps.receive_config;

        emit_cpi!(DefaultConfigSetEvent {
            eid: params.eid,
            send_uln_config: Some(params.send_uln_config.clone()),
            receive_uln_config: Some(params.receive_uln_config.clone()),
            executor_config: Some(params.executor_config.clone()),
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitDefaultConfigParams {
    pub eid: u32,
    pub send_uln_config: UlnConfig,
    pub receive_uln_config: UlnConfig,
    pub executor_config: ExecutorConfig,
}
