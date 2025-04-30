use crate::*;
use anchor_lang::solana_program::keccak::hash;
use errors::SimpleMessageLibError;
use messagelib_helper::{endpoint_verify, packet_v1_codec};

#[derive(Accounts)]
pub struct ValidatePacket<'info> {
    pub payer: Signer<'info>,
    #[account(
        seeds = [MESSAGE_LIB_SEED],
        bump = receive_library.bump,
        constraint = payer.key() == receive_library.wl_caller @SimpleMessageLibError::OnlyWhitelistedCaller
    )]
    pub receive_library: Account<'info, MessageLib>,
}

impl ValidatePacket<'_> {
    pub fn apply(ctx: &mut Context<ValidatePacket>, params: &ValidatePacketParams) -> Result<()> {
        // convert packet bytes into a packet
        let packet_slice = params.packet.as_slice();
        let payload = packet_v1_codec::payload(packet_slice);
        let payload_hash = hash(payload).to_bytes();

        let seeds = [MESSAGE_LIB_SEED, &[ctx.accounts.receive_library.bump]];
        endpoint_verify::verify(
            ctx.accounts.receive_library.endpoint_program,
            ctx.accounts.receive_library.key(),
            packet_slice,
            payload_hash,
            &seeds,
            &ctx.remaining_accounts,
        )
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ValidatePacketParams {
    pub packet: Vec<u8>,
}
