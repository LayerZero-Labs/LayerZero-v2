use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: InitDefaultReceiveLibraryParams)]
pub struct InitDefaultReceiveLibrary<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        init,
        payer = admin,
        space = 8 + ReceiveLibraryConfig::INIT_SPACE,
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump
    )]
    pub default_receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Send @LayerZeroError::OnlyReceiveLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
    pub system_program: Program<'info, System>,
}

impl InitDefaultReceiveLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<InitDefaultReceiveLibrary>,
        params: &InitDefaultReceiveLibraryParams,
    ) -> Result<()> {
        ctx.accounts.default_receive_library_config.message_lib = params.new_lib;
        ctx.accounts.default_receive_library_config.timeout = None;
        ctx.accounts.default_receive_library_config.bump = ctx.bumps.default_receive_library_config;
        emit_cpi!(DefaultReceiveLibrarySetEvent { eid: params.eid, new_lib: params.new_lib });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitDefaultReceiveLibraryParams {
    pub eid: u32,
    pub new_lib: Pubkey,
}
