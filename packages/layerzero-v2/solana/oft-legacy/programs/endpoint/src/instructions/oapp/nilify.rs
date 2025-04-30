use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: NilifyParams)]
pub struct Nilify<'info> {
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
        mut,
        seeds = [
            NONCE_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
    #[account(
        mut,
        seeds = [
            PENDING_NONCE_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = pending_inbound_nonce.bump
    )]
    pub pending_inbound_nonce: Account<'info, PendingInboundNonce>,
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
        constraint = payload_hash.hash == params.payload_hash @LayerZeroError::PayloadHashNotFound
    )]
    pub payload_hash: Account<'info, PayloadHash>,
}

/// Marks a packet as verified, but disallows execution until it is re-verified.
impl Nilify<'_> {
    pub fn apply(ctx: &mut Context<Nilify>, params: &NilifyParams) -> Result<()> {
        if params.nonce > ctx.accounts.nonce.inbound_nonce {
            ctx.accounts
                .pending_inbound_nonce
                .insert_pending_inbound_nonce(params.nonce, &mut ctx.accounts.nonce)?;
        }

        ctx.accounts.payload_hash.hash = NIL_PAYLOAD_HASH;

        emit_cpi!(PacketNilifiedEvent {
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
pub struct NilifyParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}
