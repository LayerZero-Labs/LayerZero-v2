use crate::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    token_interface::{self, Mint, MintTo, TokenAccount, TokenInterface, TransferChecked},
};
use oapp::endpoint::{
    cpi::accounts::Clear,
    instructions::{ClearParams, SendComposeParams},
    ConstructCPIContext,
};

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: LzReceiveParams)]
pub struct LzReceive<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        mut,
        seeds = [
            PEER_SEED,
            &oft_config.key().to_bytes(),
            &params.src_eid.to_be_bytes()
        ],
        bump = peer.bump,
        constraint = peer.address == params.sender @OftError::InvalidSender
    )]
    pub peer: Account<'info, Peer>,
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump
    )]
    pub oft_config: Account<'info, OftConfig>,
    #[account(
        mut,
        token::authority = oft_config,
        token::mint = token_mint,
        token::token_program = token_program,
        constraint = oft_config.ext == OftConfigExt::Adapter(token_escrow.key()) @OftError::InvalidTokenEscrow
    )]
    pub token_escrow: Option<InterfaceAccount<'info, TokenAccount>>,
    /// CHECK: the wallet address to receive the token
    #[account(address = Pubkey::from(msg_codec::send_to(&params.message)) @OftError::InvalidTokenDest)]
    pub to_address: AccountInfo<'info>,
    #[account(
        init_if_needed,
        payer = payer,
        associated_token::mint = token_mint,
        associated_token::authority = to_address,
        associated_token::token_program = token_program
    )]
    pub token_dest: InterfaceAccount<'info, TokenAccount>,
    #[account(
        mut,
        address = oft_config.token_mint,
        mint::token_program = token_program
    )]
    pub token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

impl LzReceive<'_> {
    pub fn apply(ctx: &mut Context<LzReceive>, params: &LzReceiveParams) -> Result<()> {
        let oft_config_seed = get_oft_config_seed(&ctx.accounts.oft_config);
        let seeds: &[&[u8]] =
            &[OFT_SEED, &oft_config_seed.to_bytes(), &[ctx.accounts.oft_config.bump]];

        let accounts_for_clear = &ctx.remaining_accounts[0..Clear::MIN_ACCOUNTS_LEN];
        let _ = oapp::endpoint_cpi::clear(
            ctx.accounts.oft_config.endpoint_program,
            ctx.accounts.oft_config.key(),
            accounts_for_clear,
            seeds,
            ClearParams {
                receiver: ctx.accounts.oft_config.key(),
                src_eid: params.src_eid,
                sender: params.sender,
                nonce: params.nonce,
                guid: params.guid,
                message: params.message.clone(),
            },
        )?;

        let amount_sd = msg_codec::amount_sd(&params.message);
        let amount_ld = ctx.accounts.oft_config.sd2ld(amount_sd);
        let amount_received_ld = get_post_fee_amount_ld(
            &ctx.accounts.oft_config.ext,
            &ctx.accounts.token_mint,
            amount_ld,
        )?;

        // credit
        match &ctx.accounts.oft_config.ext {
            OftConfigExt::Adapter(escrow) => {
                if let Some(escrow_acc) = &ctx.accounts.token_escrow {
                    // unlock
                    let seeds: &[&[u8]] =
                        &[OFT_SEED, &escrow.to_bytes(), &[ctx.accounts.oft_config.bump]];
                    token_interface::transfer_checked(
                        CpiContext::new(
                            ctx.accounts.token_program.to_account_info(),
                            TransferChecked {
                                from: escrow_acc.to_account_info(),
                                mint: ctx.accounts.token_mint.to_account_info(),
                                to: ctx.accounts.token_dest.to_account_info(),
                                authority: ctx.accounts.oft_config.to_account_info(),
                            },
                        )
                        .with_signer(&[&seeds]),
                        amount_ld,
                        ctx.accounts.token_mint.decimals,
                    )?;
                } else {
                    return Err(OftError::InvalidTokenEscrow.into());
                }
            },
            OftConfigExt::Native(_) => {
                // mint
                let cpi_accounts = MintTo {
                    mint: ctx.accounts.token_mint.to_account_info(),
                    to: ctx.accounts.token_dest.to_account_info(),
                    authority: ctx.accounts.oft_config.to_account_info(),
                };
                let cpi_program = ctx.accounts.token_program.to_account_info();
                let cpi_context = CpiContext::new(cpi_program, cpi_accounts);
                token_interface::mint_to(cpi_context.with_signer(&[&seeds]), amount_ld)?;
            },
        };

        let to_address = Pubkey::from(msg_codec::send_to(&params.message));
        if let Some(message) = msg_codec::compose_msg(&params.message) {
            oapp::endpoint_cpi::send_compose(
                ctx.accounts.oft_config.endpoint_program,
                ctx.accounts.oft_config.key(),
                &ctx.remaining_accounts[Clear::MIN_ACCOUNTS_LEN..],
                seeds,
                SendComposeParams {
                    to: to_address,
                    guid: params.guid,
                    index: 0, // only 1 compose msg per lzReceive
                    message: compose_msg_codec::encode(
                        params.nonce,
                        params.src_eid,
                        amount_received_ld,
                        &message,
                    ),
                },
            )?;
        }

        // Refill the rate limiter
        if let Some(rate_limiter) = ctx.accounts.peer.rate_limiter.as_mut() {
            rate_limiter.refill(amount_received_ld)?;
        }

        emit_cpi!(OFTReceived {
            guid: params.guid,
            src_eid: params.src_eid,
            to: to_address,
            amount_received_ld,
        });

        Ok(())
    }
}
