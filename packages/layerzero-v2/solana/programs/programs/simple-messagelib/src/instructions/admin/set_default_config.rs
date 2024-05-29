use crate::*;

#[derive(Accounts)]
#[instruction(params: SetDefaultConfigParams)]
pub struct SetDefaultConfig<'info> {
    pub admin: Signer<'info>,
    #[account(
        has_one = admin,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
    #[account(
        mut,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = send_config.bump
    )]
    pub send_config: Account<'info, SendConfigStore>,
    #[account(
        mut,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = receive_config.bump
    )]
    pub receive_config: Account<'info, ReceiveConfigStore>,
    pub system_program: Program<'info, System>,
}

impl SetDefaultConfig<'_> {
    pub fn apply(
        ctx: &mut Context<SetDefaultConfig>,
        params: &SetDefaultConfigParams,
    ) -> Result<()> {
        if let Some(config) = &params.send_config {
            ctx.accounts.send_config.data = config.clone();
        }

        if let Some(config) = &params.receive_config {
            ctx.accounts.receive_config.data = config.clone();
        }

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDefaultConfigParams {
    pub eid: u32,
    pub send_config: Option<Vec<u8>>,
    pub receive_config: Option<Vec<u8>>,
}
