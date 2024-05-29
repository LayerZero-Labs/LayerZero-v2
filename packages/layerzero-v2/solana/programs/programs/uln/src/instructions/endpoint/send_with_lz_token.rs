use crate::*;
use anchor_spl::token_interface::{self, Mint, TokenAccount, TokenInterface, TransferChecked};
use messagelib_helper::packet_v1_codec::encode;

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SendWithLzTokenParams)]
pub struct SendWithLzToken<'info> {
    pub endpoint: Signer<'info>,
    #[account(has_one = endpoint, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    /// The custom send config account may be uninitialized, so deserialize it only if it's initialized
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes(), &params.packet.sender.to_bytes()],
        bump
    )]
    pub send_config: AccountInfo<'info>,
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes()],
        bump = default_send_config.bump,
    )]
    pub default_send_config: Account<'info, SendConfig>,
    /// pay for the native fee
    #[account(
        mut,
        constraint = payer.key() != endpoint.key() @UlnError::InvalidPayer,
    )]
    pub payer: Signer<'info>,
    /// for native fee transfer
    pub system_program: Program<'info, System>,
    /// The token account to pay the lz token fee
    #[account(
        mut,
        token::authority = payer,
        token::mint = lz_token_mint,
        token::token_program = token_program,
    )]
    pub lz_token_source: InterfaceAccount<'info, TokenAccount>,
    /// The treasury token account to receive the lz token fee
    #[account(
        mut,
        token::mint = lz_token_mint,
        token::token_program = token_program,
    )]
    pub lz_token_treasury: InterfaceAccount<'info, TokenAccount>,
    #[account(
        address = params.lz_token_mint @UlnError::InvalidLzTokenMint,
        mint::token_program = token_program
    )]
    pub lz_token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
}

impl SendWithLzToken<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &mut Context<'_, '_, 'c, 'info, SendWithLzToken<'info>>,
        params: &SendWithLzTokenParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        let (executor_fee, dvn_fees) = assign_job_to_workers(
            &ctx.accounts.uln.key(),
            &ctx.accounts.payer,
            &params.packet,
            &params.options,
            &ctx.accounts.send_config,
            &ctx.accounts.default_send_config,
            ctx.remaining_accounts,
        )?;
        let worker_fee = executor_fee.fee + dvn_fees.iter().map(|f| f.fee).sum::<u64>();
        require!(params.native_fee >= worker_fee, UlnError::InsufficientFee);

        // the treasury configuration should be available
        let treasury = ctx.accounts.uln.treasury.as_ref().ok_or(UlnError::LzTokenUnavailable)?;
        let treasury_fee = quote_treasury(treasury, worker_fee, true)?;
        require!(params.lz_token_fee >= treasury_fee, UlnError::InsufficientFee);

        // assert the treasury receiver
        let receiver = treasury.lz_token.as_ref().unwrap().receiver;
        require!(receiver == ctx.accounts.lz_token_treasury.key(), UlnError::InvalidTreasury);

        // pay lz token fee
        if treasury_fee > 0 {
            let cpi_accounts = TransferChecked {
                from: ctx.accounts.lz_token_source.to_account_info(),
                mint: ctx.accounts.lz_token_mint.to_account_info(),
                to: ctx.accounts.lz_token_treasury.to_account_info(),
                authority: ctx.accounts.payer.to_account_info(),
            };
            let cpi_program = ctx.accounts.token_program.to_account_info();
            let cpi_context = CpiContext::new(cpi_program, cpi_accounts);
            token_interface::transfer_checked(
                cpi_context,
                treasury_fee,
                ctx.accounts.lz_token_mint.decimals,
            )?;
        }

        emit_cpi!(FeesPaidEvent {
            executor: executor_fee,
            dvns: dvn_fees,
            treasury: Some(TreasuryFee {
                treasury: receiver,
                fee: treasury_fee,
                pay_in_lz_token: true
            })
        });

        Ok((
            MessagingFee { native_fee: worker_fee, lz_token_fee: treasury_fee },
            encode(&params.packet),
        ))
    }
}
