use crate::*;
use anchor_lang::solana_program::keccak::hash;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SendComposeParams)]
pub struct SendCompose<'info> {
    pub from: Signer<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + ComposeMessageState::INIT_SPACE,
        seeds = [
            COMPOSED_MESSAGE_HASH_SEED,
            from.key.as_ref(),
            &params.to.to_bytes(),
            &params.guid[..],
            &params.index.to_be_bytes(),
            &hash(&params.message).to_bytes()
        ],
        bump
    )]
    pub compose_message: Account<'info, ComposeMessageState>,
    pub system_program: Program<'info, System>,
}


#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendComposeParams {
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
}
