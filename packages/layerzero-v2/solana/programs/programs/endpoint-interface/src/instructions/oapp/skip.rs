use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SkipParams)]
pub struct Skip<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    pub pending_inbound_nonce: UncheckedAccount<'info>,
    /// the payload hash needs to be initialized before it can be skipped and closed, in order to prevent someone
    /// from skipping a payload hash that has been initialized and can be re-verified and executed after skipping
    pub payload_hash: UncheckedAccount<'info>,
    pub endpoint: UncheckedAccount<'info>,
}

impl Skip<'_> {
    pub fn apply(_ctx: &mut Context<Skip>, _params: &SkipParams) -> Result<()> {
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
