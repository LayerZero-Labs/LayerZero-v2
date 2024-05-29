use crate::*;

use anchor_lang::solana_program::keccak::hashv;
use cpi_helper::CpiContext;

/// MESSAGING STEP 3. the oapp should pull the message out using clear()

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: ClearParams)]
pub struct Clear<'info> {
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
            &params.nonce.to_be_bytes()
        ],
        bump = payload_hash.bump,
        close = endpoint
    )]
    pub payload_hash: Account<'info, PayloadHash>,
    #[account(mut, seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
}

impl Clear<'_> {
    pub fn apply(ctx: &mut Context<Clear>, params: &ClearParams) -> Result<[u8; 32]> {
        let payload_hash = hash_payload(&params.guid, &params.message);
        require!(
            payload_hash == ctx.accounts.payload_hash.hash,
            LayerZeroError::PayloadHashNotFound
        );

        emit_cpi!(PacketDeliveredEvent {
            src_eid: params.src_eid,
            sender: params.sender,
            receiver: params.receiver,
            nonce: params.nonce,
        });
        Ok(payload_hash)
    }
}

pub fn hash_payload(guid: &[u8; 32], message: &[u8]) -> [u8; 32] {
    hashv(&[&guid[..], &message[..]]).to_bytes()
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ClearParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub guid: [u8; 32],
    pub message: Vec<u8>,
}
