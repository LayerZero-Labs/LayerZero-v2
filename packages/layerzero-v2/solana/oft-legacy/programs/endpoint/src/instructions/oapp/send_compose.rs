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

impl SendCompose<'_> {
    pub fn apply(ctx: &mut Context<SendCompose>, params: &SendComposeParams) -> Result<()> {
        ctx.accounts.compose_message.received = false;
        ctx.accounts.compose_message.bump = ctx.bumps.compose_message;

        // emit event
        emit_cpi!(ComposeSentEvent {
            from: ctx.accounts.from.key(),
            to: params.to,
            guid: params.guid,
            index: params.index,
            message: params.message.clone(),
        });

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
