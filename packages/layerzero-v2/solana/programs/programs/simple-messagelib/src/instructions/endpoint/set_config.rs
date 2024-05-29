use crate::*;

pub mod config_types {
    pub const SEND: u32 = 1;
    pub const RECEIVE: u32 = 2;
}

#[derive(Accounts)]
#[instruction(params: SetConfigParams)]
pub struct SetConfig<'info> {
    pub endpoint: Signer<'info>,
    #[account(
        has_one = endpoint,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
    #[account(
        mut,
        seeds = [SEND_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump = send_config.bump
    )]
    pub send_config: Account<'info, SendConfigStore>,
    #[account(
        mut,
        seeds = [RECEIVE_CONFIG_SEED, &params.eid.to_be_bytes(), &params.oapp.to_bytes()],
        bump = receive_config.bump
    )]
    pub receive_config: Account<'info, ReceiveConfigStore>,
}

impl SetConfig<'_> {
    pub fn apply(ctx: &mut Context<SetConfig>, params: &SetConfigParams) -> Result<()> {
        match params.config_type {
            config_types::SEND => {
                ctx.accounts.send_config.data = params.config.to_vec();
            },
            config_types::RECEIVE => {
                ctx.accounts.receive_config.data = params.config.to_vec();
            },
            _ => return Err(SimpleMessageLibError::InvalidConfigType.into()),
        }
        Ok(())
    }
}
