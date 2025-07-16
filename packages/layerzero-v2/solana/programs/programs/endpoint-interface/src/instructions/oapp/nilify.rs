use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: NilifyParams)]
pub struct Nilify<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    pub pending_inbound_nonce: UncheckedAccount<'info>,
    pub payload_hash: UncheckedAccount<'info>,
}

/// Marks a packet as verified, but disallows execution until it is re-verified.
impl Nilify<'_> {
    pub fn apply(ctx: &mut Context<Nilify>, params: &NilifyParams) -> Result<()> {
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
