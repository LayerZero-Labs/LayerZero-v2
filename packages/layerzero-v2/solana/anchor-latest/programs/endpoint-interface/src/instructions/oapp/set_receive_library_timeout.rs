use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetReceiveLibraryTimeoutParams)]
pub struct SetReceiveLibraryTimeout<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.receiver.as_ref()],
        bump = oapp_registry.bump,
        constraint = signer.key() == params.receiver
            || signer.key() == oapp_registry.delegate @LayerZeroError::Unauthorized
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        mut,
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, params.receiver.as_ref(), &params.eid.to_be_bytes()],
        bump = receive_library_config.bump,
        constraint = receive_library_config.message_lib != DEFAULT_MESSAGE_LIB @LayerZeroError::OnlyNonDefaultLib,
    )]
    pub receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Send @LayerZeroError::OnlyReceiveLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetReceiveLibraryTimeoutParams {
    pub receiver: Pubkey,
    pub eid: u32,
    pub lib: Pubkey,
    pub expiry: u64,
}
