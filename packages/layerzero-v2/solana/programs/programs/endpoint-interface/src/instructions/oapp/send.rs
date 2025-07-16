use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 1

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SendParams)]
pub struct Send<'info> {
    pub sender: Signer<'info>,
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    pub send_library_config: UncheckedAccount<'info>,
    pub default_send_library_config: UncheckedAccount<'info>,
    /// The PDA signer to the send library when the endpoint calls the send library.
    pub send_library_info: UncheckedAccount<'info>,
    pub endpoint: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
}

impl Send<'_> {
    pub fn apply(_ctx: &mut Context<Send>, _params: &SendParams) -> Result<MessagingReceipt> {
        Ok(MessagingReceipt {
            guid: [0; 32],
            nonce: 0,
            fee: MessagingFee { native_fee: 0, lz_token_fee: 0 },
        })
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendParams {
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub message: Vec<u8>,
    pub options: Vec<u8>,
    pub native_fee: u64,
    pub lz_token_fee: u64,
}
