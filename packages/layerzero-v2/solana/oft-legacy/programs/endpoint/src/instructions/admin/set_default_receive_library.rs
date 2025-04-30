use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SetDefaultReceiveLibraryParams)]
pub struct SetDefaultReceiveLibrary<'info> {
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        mut,
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.eid.to_be_bytes()],
        bump = default_receive_library_config.bump,
        constraint = default_receive_library_config.message_lib != params.new_lib @LayerZeroError::SameValue
    )]
    pub default_receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [MESSAGE_LIB_SEED, &params.new_lib.to_bytes()],
        bump = message_lib_info.bump,
        constraint = message_lib_info.message_lib_type != MessageLibType::Send @LayerZeroError::OnlyReceiveLib
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
}

impl SetDefaultReceiveLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<SetDefaultReceiveLibrary>,
        params: &SetDefaultReceiveLibraryParams,
    ) -> Result<()> {
        let old_lib = ctx.accounts.default_receive_library_config.message_lib;
        ctx.accounts.default_receive_library_config.message_lib = params.new_lib;
        emit_cpi!(DefaultReceiveLibrarySetEvent { eid: params.eid, new_lib: params.new_lib });

        let timeout = if params.grace_period > 0 {
            Some(ReceiveLibraryTimeout {
                message_lib: old_lib,
                expiry: params.grace_period + Clock::get()?.slot,
            })
        } else {
            None
        };
        ctx.accounts.default_receive_library_config.timeout = timeout.clone();
        emit_cpi!(DefaultReceiveLibraryTimeoutSetEvent { eid: params.eid, timeout });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDefaultReceiveLibraryParams {
    pub eid: u32,
    pub new_lib: Pubkey,
    pub grace_period: u64,
}
