use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 2
/// requires init_verify()
#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: VerifyParams)]
pub struct Verify<'info> {
    /// The PDA of the receive library.
    pub receive_library: Signer<'info>,
    pub receive_library_config: UncheckedAccount<'info>,
    pub default_receive_library_config: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    pub pending_inbound_nonce: UncheckedAccount<'info>,
    pub payload_hash: UncheckedAccount<'info>,
}

impl Verify<'_> {
    pub fn apply(_ctx: &mut Context<Verify>, _params: &VerifyParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct VerifyParams {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}
