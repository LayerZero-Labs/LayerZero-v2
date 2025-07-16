use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SendComposeParams)]
pub struct SendCompose<'info> {
    pub from: Signer<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub compose_message: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

impl SendCompose<'_> {
    pub fn apply(_ctx: &mut Context<SendCompose>, _params: &SendComposeParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendComposeParams {
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
}
