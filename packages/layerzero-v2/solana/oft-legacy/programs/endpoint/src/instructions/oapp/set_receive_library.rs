use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetReceiveLibraryParams)]
pub struct SetReceiveLibrary<'info> {
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
        constraint = receive_library_config.message_lib != params.new_lib @LayerZeroError::SameValue
    )]
    pub receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Send @LayerZeroError::OnlyReceiveLib
    )]
    pub message_lib_info: Option<Account<'info, MessageLibInfo>>,
}

impl SetReceiveLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<SetReceiveLibrary>,
        params: &SetReceiveLibraryParams,
    ) -> Result<()> {
        if params.new_lib != DEFAULT_MESSAGE_LIB {
            // If the new library is not the default library, the message_lib_info must be present
            require!(ctx.accounts.message_lib_info.is_some(), LayerZeroError::AccountNotFound);
        }
        let old_lib = ctx.accounts.receive_library_config.message_lib;
        ctx.accounts.receive_library_config.message_lib = params.new_lib;

        emit_cpi!(ReceiveLibrarySetEvent {
            receiver: params.receiver,
            eid: params.eid,
            new_lib: params.new_lib,
        });

        let timeout = if params.grace_period > 0 {
            // to simplify the logic, we only allow to set timeout if neither the new lib nor old lib is DEFAULT_MESSAGE_LIB, which would read the default timeout configurations
            // (1) if the oapp wants to fall back to the DEFAULT, then set the newLib to DEFAULT with grace period == 0
            // (2) if the oapp wants to change to a non DEFAULT from DEFAULT, then set the newLib to 'non-default' with grace_period == 0, then use set_receive_library_timeout() interface
            require!(
                old_lib != DEFAULT_MESSAGE_LIB && params.new_lib != DEFAULT_MESSAGE_LIB,
                LayerZeroError::OnlyNonDefaultLib
            );
            Some(ReceiveLibraryTimeout {
                message_lib: old_lib,
                expiry: params.grace_period + Clock::get()?.slot,
            })
        } else {
            None
        };
        ctx.accounts.receive_library_config.timeout = timeout.clone();

        emit_cpi!(ReceiveLibraryTimeoutSetEvent {
            receiver: params.receiver,
            eid: params.eid,
            timeout,
        });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetReceiveLibraryParams {
    pub receiver: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
    pub grace_period: u64,
}
