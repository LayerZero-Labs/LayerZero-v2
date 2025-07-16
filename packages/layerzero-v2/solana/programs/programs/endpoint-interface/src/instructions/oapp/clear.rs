use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 3. the oapp should pull the message out using clear()

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: ClearParams)]
pub struct Clear<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    /// close the account and return the lamports to endpoint settings account
    pub payload_hash: UncheckedAccount<'info>,
    pub endpoint: UncheckedAccount<'info>,
}

impl Clear<'_> {
    pub fn apply(ctx: &mut Context<Clear>, params: &ClearParams) -> Result<[u8; 32]> {
        Ok([0u8; 32])
    }
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
