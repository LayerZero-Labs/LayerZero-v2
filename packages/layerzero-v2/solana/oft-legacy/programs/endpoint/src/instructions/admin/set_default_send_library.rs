use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SetDefaultSendLibraryParams)]
pub struct SetDefaultSendLibrary<'info> {
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        mut,
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = default_send_library_config.bump,
        constraint = default_send_library_config.message_lib != params.new_lib @LayerZeroError::SameValue
    )]
    pub default_send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Receive @LayerZeroError::OnlySendLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
}

impl SetDefaultSendLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<SetDefaultSendLibrary>,
        params: &SetDefaultSendLibraryParams,
    ) -> Result<()> {
        ctx.accounts.default_send_library_config.message_lib = params.new_lib;
        emit_cpi!(DefaultSendLibrarySetEvent { eid: params.eid, new_lib: params.new_lib });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDefaultSendLibraryParams {
    pub eid: u32,
    pub new_lib: Pubkey,
}
