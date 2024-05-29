use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SetDefaultConfigParams)]
pub struct SetDefaultConfig<'info> {
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    #[account(
        mut,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = send_config.bump
    )]
    pub send_config: Account<'info, SendConfig>,
    #[account(
        mut,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = receive_config.bump
    )]
    pub receive_config: Account<'info, ReceiveConfig>,
}

impl SetDefaultConfig<'_> {
    pub fn apply(
        ctx: &mut Context<SetDefaultConfig>,
        params: &SetDefaultConfigParams,
    ) -> Result<()> {
        if let Some(config) = &params.send_uln_config {
            ctx.accounts.send_config.uln.set_default_config(config)?;
        }

        if let Some(config) = &params.receive_uln_config {
            ctx.accounts.receive_config.uln.set_default_config(config)?;
        }

        if let Some(config) = &params.executor_config {
            ctx.accounts.send_config.executor.set_default_config(config)?;
        }

        emit_cpi!(DefaultConfigSetEvent {
            eid: params.eid,
            send_uln_config: params.send_uln_config.clone(),
            receive_uln_config: params.receive_uln_config.clone(),
            executor_config: params.executor_config.clone(),
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDefaultConfigParams {
    pub eid: u32,
    pub send_uln_config: Option<UlnConfig>,
    pub receive_uln_config: Option<UlnConfig>,
    pub executor_config: Option<ExecutorConfig>,
}
