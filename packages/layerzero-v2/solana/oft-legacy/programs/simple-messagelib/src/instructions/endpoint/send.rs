use crate::*;
use anchor_lang::solana_program::{program, system_instruction};
use messagelib_helper::packet_v1_codec::encode;

#[derive(Accounts)]
#[instruction(params: SendParams)]
pub struct Send<'info> {
    /// The message lib authority of the endpoint
    pub endpoint: Signer<'info>,
    /// receive the native fee
    #[account(
        mut,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump,
        has_one = endpoint,
        constraint = message_lib.fee <= params.native_fee @SimpleMessageLibError::InsufficientFee
    )]
    pub message_lib: Account<'info, MessageLib>,
    /// pay for the native fee
    #[account(mut)]
    pub payer: Signer<'info>,
    /// for native fee transfer
    pub system_program: Program<'info, System>,
}

impl Send<'_> {
    pub fn apply(ctx: &mut Context<Send>, params: &SendParams) -> Result<(MessagingFee, Vec<u8>)> {
        // Transfer the native fee from the payer to the message lib if there is any
        if ctx.accounts.message_lib.fee > 0 {
            program::invoke(
                &system_instruction::transfer(
                    ctx.accounts.payer.key,
                    &ctx.accounts.message_lib.key(),
                    ctx.accounts.message_lib.fee,
                ),
                &[ctx.accounts.payer.to_account_info(), ctx.accounts.message_lib.to_account_info()],
            )?;
        }

        Ok((
            MessagingFee { native_fee: ctx.accounts.message_lib.fee, lz_token_fee: 0 },
            encode(&params.packet),
        ))
    }
}
