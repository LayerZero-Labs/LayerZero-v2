use crate::*;
use anchor_lang::solana_program::{program, system_instruction};
use anchor_spl::token_interface::{self, Mint, TokenAccount, TokenInterface, TransferChecked};
use messagelib_helper::packet_v1_codec::encode;

#[derive(Accounts)]
#[instruction(params: SendWithLzTokenParams)]
pub struct SendWithLzToken<'info> {
    /// The message lib authority of the endpoint
    pub endpoint: Signer<'info>,
    /// receive the native fee
    #[account(
        mut,
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib.bump,
        has_one = endpoint,
        constraint = message_lib.fee <= params.native_fee @SimpleMessageLibError::InsufficientFee,
        constraint = message_lib.lz_token_fee <= params.lz_token_fee @SimpleMessageLibError::InsufficientFee
    )]
    pub message_lib: Account<'info, MessageLib>,
    #[account(
        mut,
        token::authority = message_lib,
        token::mint = lz_token_mint,
        token::token_program = token_program,
    )]
    pub message_lib_lz_token: InterfaceAccount<'info, TokenAccount>,
    /// pay for the native fee
    #[account(mut)]
    pub payer: Signer<'info>,
    /// The token account to pay the lz token fee
    #[account(
        mut,
        token::authority = payer,
        token::mint = lz_token_mint,
        token::token_program = token_program,
    )]
    pub lz_token_source: InterfaceAccount<'info, TokenAccount>,
    #[account(
        address = params.lz_token_mint @SimpleMessageLibError::InvalidLzTokenMint,
        mint::token_program = token_program
    )]
    pub lz_token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    /// for native fee transfer
    pub system_program: Program<'info, System>,
}

impl SendWithLzToken<'_> {
    pub fn apply(
        ctx: &mut Context<SendWithLzToken>,
        params: &SendWithLzTokenParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
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

        // Transfer the lz token fee from the payer to the message lib if there is any
        let lz_token_fee = ctx.accounts.message_lib.lz_token_fee;
        if lz_token_fee > 0 {
            let cpi_accounts = TransferChecked {
                from: ctx.accounts.lz_token_source.to_account_info(),
                mint: ctx.accounts.lz_token_mint.to_account_info(),
                to: ctx.accounts.message_lib_lz_token.to_account_info(),
                authority: ctx.accounts.payer.to_account_info(),
            };
            let cpi_program = ctx.accounts.token_program.to_account_info();
            let cpi_context = CpiContext::new(cpi_program, cpi_accounts);

            token_interface::transfer_checked(
                cpi_context,
                lz_token_fee,
                ctx.accounts.lz_token_mint.decimals,
            )?;
        }

        Ok((
            MessagingFee { native_fee: ctx.accounts.message_lib.fee, lz_token_fee },
            encode(&params.packet),
        ))
    }
}
