use crate::*;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: RegisterLibraryParams)]
pub struct RegisterLibrary<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(has_one = admin, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        init,
        payer = admin,
        space = 8 + MessageLibInfo::INIT_SPACE,
        seeds = [
            MESSAGE_LIB_SEED,
            &Pubkey::find_program_address(
                &[MESSAGE_LIB_SEED],
                &params.lib_program,
            ).0.to_bytes()
        ],
        bump
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
    pub system_program: Program<'info, System>,
}

impl RegisterLibrary<'_> {
    pub fn apply(ctx: &mut Context<RegisterLibrary>, params: RegisterLibraryParams) -> Result<()> {
        // to prevent the endpoint program from self recursion
        require!(params.lib_program != ID, LayerZeroError::InvalidMessageLib);

        ctx.accounts.message_lib_info.message_lib_type = params.lib_type;
        ctx.accounts.message_lib_info.bump = ctx.bumps.message_lib_info;

        let (message_lib, bump) =
            Pubkey::find_program_address(&[MESSAGE_LIB_SEED], &params.lib_program);
        ctx.accounts.message_lib_info.message_lib_bump = bump;

        emit_cpi!(LibraryRegisteredEvent {
            new_lib: message_lib,
            new_lib_program: params.lib_program
        });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct RegisterLibraryParams {
    pub lib_program: Pubkey,
    pub lib_type: MessageLibType,
}
