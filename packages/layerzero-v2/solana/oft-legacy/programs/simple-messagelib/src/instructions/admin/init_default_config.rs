use crate::*;

#[derive(Accounts)]
#[instruction(params: InitDefaultConfigParams)]
pub struct InitDefaultConfig<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        has_one = admin,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
    #[account(
        init,
        payer = admin,
        space = 8 + SendConfigStore::INIT_SPACE,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub send_config: Account<'info, SendConfigStore>,
    #[account(
        init,
        payer = admin,
        space = 8 + ReceiveConfigStore::INIT_SPACE,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub receive_config: Account<'info, ReceiveConfigStore>,
    pub system_program: Program<'info, System>,
}

impl InitDefaultConfig<'_> {
    pub fn apply(
        ctx: &mut Context<InitDefaultConfig>,
        params: &InitDefaultConfigParams,
    ) -> Result<()> {
        if let Some(config) = &params.send_config {
            ctx.accounts.send_config.data = config.clone();
        }

        if let Some(config) = &params.receive_config {
            ctx.accounts.receive_config.data = config.clone();
        }

        ctx.accounts.send_config.bump = ctx.bumps.send_config;
        ctx.accounts.receive_config.bump = ctx.bumps.receive_config;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitDefaultConfigParams {
    pub eid: u32,
    pub send_config: Option<Vec<u8>>,
    pub receive_config: Option<Vec<u8>>,
}
