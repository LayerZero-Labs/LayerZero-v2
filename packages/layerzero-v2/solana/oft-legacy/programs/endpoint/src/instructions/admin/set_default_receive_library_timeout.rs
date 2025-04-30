use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SetDefaultReceiveLibraryTimeoutParams)]
pub struct SetDefaultReceiveLibraryTimeout<'info> {
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        mut,
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = default_receive_library_config.bump
    )]
    pub default_receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Send @LayerZeroError::OnlyReceiveLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
}

impl SetDefaultReceiveLibraryTimeout<'_> {
    pub fn apply(
        ctx: &mut Context<SetDefaultReceiveLibraryTimeout>,
        params: &SetDefaultReceiveLibraryTimeoutParams,
    ) -> Result<()> {
        let timeout = if params.expiry > 0 {
            // must be greater than now
            require!(params.expiry > Clock::get()?.slot, LayerZeroError::InvalidExpiry);
            Some(ReceiveLibraryTimeout { message_lib: params.lib, expiry: params.expiry })
        } else {
            None
        };
        ctx.accounts.default_receive_library_config.timeout = timeout.clone();
        emit_cpi!(DefaultReceiveLibraryTimeoutSetEvent { eid: params.eid, timeout });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDefaultReceiveLibraryTimeoutParams {
    pub eid: u32,
    pub lib: Pubkey,
    pub expiry: u64,
}
