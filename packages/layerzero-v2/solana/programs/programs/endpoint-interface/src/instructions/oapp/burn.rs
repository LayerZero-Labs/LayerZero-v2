use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: BurnParams)]
pub struct Burn<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    /// close the account and return the lamports to endpoint settings account
    pub payload_hash: UncheckedAccount<'info>,
    pub endpoint: UncheckedAccount<'info>,
}

/// Marks a nonce as unexecutable and un-verifiable. The nonce can never be re-verified or executed.
/// Only packets with nonce less than or equal to the execution nonce and is not empty can be
/// burned.
impl Burn<'_> {
    pub fn apply(_ctx: &mut Context<Burn>, _params: &BurnParams) -> Result<()> {
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
