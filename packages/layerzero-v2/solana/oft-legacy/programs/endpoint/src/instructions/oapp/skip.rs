use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SkipParams)]
pub struct Skip<'info> {
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
        bump = nonce.bump,
        constraint = params.nonce == nonce.inbound_nonce + 1 @LayerZeroError::InvalidNonce
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
    /// the payload hash needs to be initialized before it can be skipped and closed, in order to prevent someone
    /// from skipping a payload hash that has been initialized and can be re-verified and executed after skipping
    #[account(
        mut,
        seeds = [
            PAYLOAD_HASH_SEED,
            &params.receiver.to_bytes(),
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

impl Skip<'_> {
    pub fn apply(ctx: &mut Context<Skip>, params: &SkipParams) -> Result<()> {
        ctx.accounts
            .pending_inbound_nonce
            .insert_pending_inbound_nonce(params.nonce, &mut ctx.accounts.nonce)?;

        emit_cpi!(InboundNonceSkippedEvent {
            src_eid: params.src_eid,
            sender: params.sender,
            receiver: params.receiver,
            nonce: params.nonce,
        });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SkipParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
}
