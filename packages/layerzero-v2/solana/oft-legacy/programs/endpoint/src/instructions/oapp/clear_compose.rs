use crate::*;
use anchor_lang::solana_program::keccak::hash;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: ClearComposeParams)]
pub struct ClearCompose<'info> {
    pub to: Signer<'info>,
    #[account(
        mut,
        seeds = [
            COMPOSED_MESSAGE_HASH_SEED,
            &params.from.to_bytes(),
            to.key.as_ref(),
            &params.guid[..],
            &params.index.to_be_bytes(),
            &hash(&params.message).to_bytes()
        ],
        bump = compose_message.bump,
        constraint = !compose_message.received @LayerZeroError::ComposeNotFound
    )]
    pub compose_message: Account<'info, ComposeMessageState>,
}

impl ClearCompose<'_> {
    pub fn apply(ctx: &mut Context<ClearCompose>, params: &ClearComposeParams) -> Result<()> {
        // mark as received instead of closing the account,
        // otherwise the message could be delivered again
        ctx.accounts.compose_message.received = true;

        // emit event
        emit_cpi!(ComposeDeliveredEvent {
            from: params.from,
            to: ctx.accounts.to.key(),
            guid: params.guid,
            index: params.index,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ClearComposeParams {
    pub from: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
}
