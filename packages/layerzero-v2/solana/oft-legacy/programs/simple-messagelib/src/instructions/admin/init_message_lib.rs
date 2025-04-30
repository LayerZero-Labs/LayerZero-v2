use crate::*;

#[derive(Accounts)]
pub struct InitMessageLib<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + MessageLib::INIT_SPACE,
        seeds = [MESSAGE_LIB_SEED],
        bump
    )]
    pub message_lib: Account<'info, MessageLib>,
    pub system_program: Program<'info, System>,
}

impl InitMessageLib<'_> {
    pub fn apply(ctx: &mut Context<InitMessageLib>, params: &InitMessageLibParams) -> Result<()> {
        ctx.accounts.message_lib.eid = params.eid;
        ctx.accounts.message_lib.endpoint = params.endpoint;
        ctx.accounts.message_lib.endpoint_program = params.endpoint_program;
        ctx.accounts.message_lib.admin = params.admin;
        ctx.accounts.message_lib.fee = params.fee;
        ctx.accounts.message_lib.lz_token_fee = params.lz_token_fee;
        ctx.accounts.message_lib.bump = ctx.bumps.message_lib;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitMessageLibParams {
    pub eid: u32,
    pub endpoint: Pubkey, // the PDA signer of the endpoint program
    pub endpoint_program: Pubkey,
    pub admin: Pubkey,
    pub fee: u64,
    pub lz_token_fee: u64,
}
