use crate::*;
use anchor_lang::solana_program::keccak;
use messagelib_helper::packet_v1_codec::PACKET_HEADER_SIZE;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: VerifyParams)]
pub struct Verify<'info> {
    pub dvn: Signer<'info>,
    #[account(
        mut,
        seeds = [
            CONFIRMATIONS_SEED,
            &keccak::hash(params.packet_header.as_slice()).to_bytes(),
            &params.payload_hash[..],
            dvn.key.as_ref()
        ],
        bump = confirmations.bump
    )]
    pub confirmations: Account<'info, Confirmations>,
}

impl Verify<'_> {
    pub fn apply(ctx: &mut Context<Verify>, params: &VerifyParams) -> Result<()> {
        ctx.accounts.confirmations.value = Some(params.confirmations);

        emit_cpi!(PayloadVerifiedEvent {
            dvn: ctx.accounts.dvn.key(),
            header: params.packet_header,
            confirmations: params.confirmations,
            proof_hash: params.payload_hash,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct VerifyParams {
    pub packet_header: [u8; PACKET_HEADER_SIZE],
    pub payload_hash: [u8; 32],
    pub confirmations: u64,
}
