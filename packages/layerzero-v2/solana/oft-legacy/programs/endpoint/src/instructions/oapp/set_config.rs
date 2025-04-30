use crate::*;
use cpi_helper::CpiContext;

#[derive(CpiContext, Accounts)]
#[instruction(params: SetConfigParams)]
pub struct SetConfig<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.oapp.as_ref()],
        bump = oapp_registry.bump,
        constraint = signer.key() == params.oapp
            || signer.key() == oapp_registry.delegate @LayerZeroError::Unauthorized
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    /// The PDA signer to the message lib when the endpoint calls the message lib program
    #[account(
        seeds = [MESSAGE_LIB_SEED, &message_lib.key.to_bytes()],
        bump = message_lib_info.bump,
        constraint = !message_lib_info.to_account_info().is_writable @LayerZeroError::ReadOnlyAccount
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
    /// the pda of the message_lib_program
    #[account(
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib_info.message_lib_bump,
        seeds::program = message_lib_program
    )]
    pub message_lib: AccountInfo<'info>,
    /// CHECK: already checked with the message_lib account
    pub message_lib_program: UncheckedAccount<'info>,
}

impl SetConfig<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &mut Context<'_, '_, 'c, 'info, SetConfig<'info>>,
        params: &SetConfigParams,
    ) -> Result<()> {
        let seeds: &[&[&[u8]]] = &[&[
            MESSAGE_LIB_SEED,
            ctx.accounts.message_lib.key.as_ref(),
            &[ctx.accounts.message_lib_info.bump],
        ]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.message_lib_program.to_account_info(),
            messagelib_interface::cpi::accounts::Interface {
                endpoint: ctx.accounts.message_lib_info.to_account_info(),
            },
            seeds,
        )
        .with_remaining_accounts(ctx.remaining_accounts.to_vec());
        messagelib_interface::cpi::set_config(cpi_ctx, params.clone())
    }
}
