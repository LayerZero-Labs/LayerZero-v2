use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: InitDefaultSendLibraryParams)]
pub struct InitDefaultSendLibrary<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        init,
        payer = admin,
        space = 8 + SendLibraryConfig::INIT_SPACE,
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub default_send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Receive @LayerZeroError::OnlySendLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
    pub system_program: Program<'info, System>,
}

impl InitDefaultSendLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<InitDefaultSendLibrary>,
        params: &InitDefaultSendLibraryParams,
    ) -> Result<()> {
        ctx.accounts.default_send_library_config.message_lib = params.new_lib;
        ctx.accounts.default_send_library_config.bump = ctx.bumps.default_send_library_config;
        emit_cpi!(DefaultSendLibrarySetEvent { eid: params.eid, new_lib: params.new_lib });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitDefaultSendLibraryParams {
    pub eid: u32,
    pub new_lib: Pubkey,
}
