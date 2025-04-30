use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: BurnParams)]
pub struct Burn<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.receiver.as_ref()],
        bump = oapp_registry.bump,
        constraint = signer.key() == params.receiver
            || signer.key() == oapp_registry.delegate @LayerZeroError::Unauthorized
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        seeds = [
            NONCE_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = nonce.bump,
        constraint = params.nonce <= nonce.inbound_nonce @LayerZeroError::InvalidNonce
    )]
    pub nonce: Account<'info, Nonce>,
    /// close the account and return the lamports to endpoint settings account
    #[account(
        mut,
        seeds = [
            PAYLOAD_HASH_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..],
            &params.nonce.to_be_bytes(),
        ],
        bump = payload_hash.bump,
        constraint = payload_hash.hash == params.payload_hash @LayerZeroError::PayloadHashNotFound,
        close = endpoint
    )]
    pub payload_hash: Account<'info, PayloadHash>,
    #[account(mut, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
}

/// Marks a nonce as unexecutable and un-verifiable. The nonce can never be re-verified or executed.
/// Only packets with nonce less than or equal to the execution nonce and is not empty can be
/// burned.
impl Burn<'_> {
    pub fn apply(ctx: &mut Context<Burn>, params: &BurnParams) -> Result<()> {
        emit_cpi!(PacketBurntEvent {
            src_eid: params.src_eid,
            sender: params.sender,
            receiver: params.receiver,
            nonce: params.nonce,
            payload_hash: params.payload_hash,
        });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct BurnParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}
