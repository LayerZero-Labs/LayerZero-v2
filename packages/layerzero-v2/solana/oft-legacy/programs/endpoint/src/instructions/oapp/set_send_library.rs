use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetSendLibraryParams)]
pub struct SetSendLibrary<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.sender.as_ref()],
        bump = oapp_registry.bump,
        constraint = signer.key() == params.sender
            || signer.key() == oapp_registry.delegate @LayerZeroError::Unauthorized
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        mut,
        seeds = [SEND_LIBRARY_CONFIG_SEED, params.sender.as_ref(), &params.eid.to_be_bytes()],
        bump = send_library_config.bump,
        constraint = send_library_config.message_lib != params.new_lib @LayerZeroError::SameValue
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Receive @LayerZeroError::OnlySendLib
    )]
    pub message_lib_info: Option<Account<'info, MessageLibInfo>>,
}

impl SetSendLibrary<'_> {
    pub fn apply(ctx: &mut Context<SetSendLibrary>, params: &SetSendLibraryParams) -> Result<()> {
        if params.new_lib != DEFAULT_MESSAGE_LIB {
            // If the new library is not the default library, the message_lib_info must be present
            require!(ctx.accounts.message_lib_info.is_some(), LayerZeroError::AccountNotFound);
        }
        ctx.accounts.send_library_config.message_lib = params.new_lib;

        emit_cpi!(SendLibrarySetEvent {
            sender: params.sender,
            eid: params.eid,
            new_lib: params.new_lib,
        });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetSendLibraryParams {
    pub sender: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
}
