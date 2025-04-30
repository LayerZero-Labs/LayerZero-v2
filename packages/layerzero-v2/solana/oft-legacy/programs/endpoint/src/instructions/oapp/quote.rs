use crate::*;
use cpi_helper::CpiContext;

/// MESSAGING STEP 0
/// don't need to separate quote and quote_with_lz_token as it does not process payment on quote()
#[derive(CpiContext, Accounts)]
#[instruction(params: QuoteParams)]
pub struct Quote<'info> {
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.sender.to_bytes(), &params.dst_eid.to_be_bytes()],
        bump = send_library_config.bump
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.dst_eid.to_be_bytes()],
        bump = default_send_library_config.bump
    )]
    pub default_send_library_config: Account<'info, SendLibraryConfig>,
    /// The PDA signer to the send library when the endpoint calls the send library.
    #[account(
        seeds = [
            MESSAGE_LIB_SEED,
            &get_send_library(
                &send_library_config,
                &default_send_library_config
            ).key().to_bytes()
        ],
        bump = send_library_info.bump,
        constraint = !send_library_info.to_account_info().is_writable @LayerZeroError::ReadOnlyAccount
    )]
    pub send_library_info: Account<'info, MessageLibInfo>,
    #[account(seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        seeds = [
            NONCE_SEED,
            &params.sender.to_bytes(),
            &params.dst_eid.to_be_bytes(),
            &params.receiver[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
}

impl Quote<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &Context<'_, '_, 'c, 'info, Quote<'info>>,
        params: &QuoteParams,
    ) -> Result<MessagingFee> {
        // assert all accounts are non-writable
        for account in ctx.remaining_accounts {
            require!(!account.is_writable, LayerZeroError::WritableAccountNotAllowed)
        }

        let nonce = ctx.accounts.nonce.outbound_nonce + 1;
        let packet = Packet {
            nonce,
            src_eid: ctx.accounts.endpoint.eid,
            sender: params.sender,
            dst_eid: params.dst_eid,
            receiver: params.receiver,
            guid: get_guid(
                nonce,
                ctx.accounts.endpoint.eid,
                params.sender,
                params.dst_eid,
                params.receiver,
            ),
            message: params.message.clone(),
        };

        let send_library = assert_send_library(
            &ctx.accounts.send_library_info,
            &ctx.accounts.send_library_program.key,
            &ctx.accounts.send_library_config,
            &ctx.accounts.default_send_library_config,
        )?;

        // call the send library
        if params.pay_in_lz_token {
            require!(
                ctx.accounts.endpoint.lz_token_mint.is_some(),
                LayerZeroError::LzTokenUnavailable
            );
        }
        let quote_params = messagelib_interface::QuoteParams {
            packet,
            options: params.options.clone(),
            pay_in_lz_token: params.pay_in_lz_token,
        };
        let seeds: &[&[&[u8]]] =
            &[&[MESSAGE_LIB_SEED, send_library.as_ref(), &[ctx.accounts.send_library_info.bump]]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.send_library_program.to_account_info(),
            messagelib_interface::cpi::accounts::Interface {
                endpoint: ctx.accounts.send_library_info.to_account_info(),
            },
            seeds,
        )
        .with_remaining_accounts(ctx.remaining_accounts.to_vec());
        Ok(messagelib_interface::cpi::quote(cpi_ctx, quote_params)?.get())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteParams {
    pub sender: Pubkey,
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub message: Vec<u8>,
    pub options: Vec<u8>,
    pub pay_in_lz_token: bool,
}
