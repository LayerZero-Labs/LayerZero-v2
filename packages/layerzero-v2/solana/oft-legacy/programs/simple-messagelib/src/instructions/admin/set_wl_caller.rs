use crate::*;

#[derive(Accounts)]
pub struct SetWlCaller<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        has_one = admin,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump
    )]
    pub message_lib: Account<'info, MessageLib>,
}

impl SetWlCaller<'_> {
    pub fn apply(ctx: &mut Context<SetWlCaller>, params: &SetWlCallerParams) -> Result<()> {
        ctx.accounts.message_lib.wl_caller = params.new_caller;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetWlCallerParams {
    pub new_caller: Pubkey,
}
