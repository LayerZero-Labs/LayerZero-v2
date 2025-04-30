use crate::*;

#[derive(Accounts)]
#[instruction(params: InitVerifyParams)]
pub struct InitVerify<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        seeds = [
            NONCE_SEED,
            &params.receiver.to_bytes(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = nonce.bump,
        constraint = params.nonce > nonce.inbound_nonce
    )]
    pub nonce: Account<'info, Nonce>,
    #[account(
        init,
        payer = payer,
        space = 8 + PayloadHash::INIT_SPACE,
        seeds = [
            PAYLOAD_HASH_SEED,
            &params.receiver.to_bytes(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..],
            &params.nonce.to_be_bytes()
        ],
        bump
    )]
    pub payload_hash: Account<'info, PayloadHash>,
    pub system_program: Program<'info, System>,
}

impl InitVerify<'_> {
    pub fn apply(ctx: &mut Context<InitVerify>, _params: &InitVerifyParams) -> Result<()> {
        ctx.accounts.payload_hash.hash = EMPTY_PAYLOAD_HASH;
        ctx.accounts.payload_hash.bump = ctx.bumps.payload_hash;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitVerifyParams {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
}
