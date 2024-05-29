use crate::*;
use anchor_lang::solana_program::keccak;
use messagelib_helper::packet_v1_codec::PACKET_HEADER_SIZE;

#[derive(Accounts)]
#[instruction(params: InitVerifyParams)]
pub struct InitVerify<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + Confirmations::INIT_SPACE,
        seeds = [
            CONFIRMATIONS_SEED,
            &keccak::hash(params.packet_header.as_slice()).to_bytes(),
            &params.payload_hash[..],
            &params.dvn.to_bytes()
        ],
        bump
    )]
    pub confirmations: Account<'info, Confirmations>,
    pub system_program: Program<'info, System>,
}

impl InitVerify<'_> {
    pub fn apply(ctx: &mut Context<InitVerify>, _params: &InitVerifyParams) -> Result<()> {
        ctx.accounts.confirmations.value = None;
        ctx.accounts.confirmations.bump = ctx.bumps.confirmations;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitVerifyParams {
    pub packet_header: [u8; PACKET_HEADER_SIZE],
    pub payload_hash: [u8; 32],
    pub dvn: Pubkey,
}
