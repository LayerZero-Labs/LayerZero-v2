use crate::*;
use oapp::endpoint::{instructions::QuoteParams as EndpointQuoteParams, MessagingFee};

use anchor_spl::token_2022::spl_token_2022::{
    extension::{
        transfer_fee::{TransferFee, TransferFeeConfig},
        BaseStateWithExtensions, StateWithExtensions,
    },
    state::Mint,
};

#[derive(Accounts)]
#[instruction(params: QuoteParams)]
pub struct Quote<'info> {
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump
    )]
    pub oft_config: Account<'info, OftConfig>,
    #[account(
        seeds = [
            PEER_SEED,
            &oft_config.key().to_bytes(),
            &params.dst_eid.to_be_bytes()
        ],
        bump = peer.bump
    )]
    pub peer: Account<'info, Peer>,
    #[account(
        seeds = [
            ENFORCED_OPTIONS_SEED,
            &oft_config.key().to_bytes(),
            &params.dst_eid.to_be_bytes()
        ],
        bump = enforced_options.bump
    )]
    pub enforced_options: Account<'info, EnforcedOptions>,
    #[account(address = oft_config.token_mint)]
    pub token_mint: InterfaceAccount<'info, anchor_spl::token_interface::Mint>,
}

impl Quote<'_> {
    pub fn apply(ctx: &Context<Quote>, params: &QuoteParams) -> Result<MessagingFee> {
        // 1. Quote the amount with token2022 fee and dedust it
        let amount_received_ld = ctx.accounts.oft_config.remove_dust(get_post_fee_amount_ld(
            &ctx.accounts.oft_config.ext,
            &ctx.accounts.token_mint,
            params.amount_ld,
        )?);
        require!(amount_received_ld >= params.min_amount_ld, OftError::SlippageExceeded);

        // calling endpoint cpi
        oapp::endpoint_cpi::quote(
            ctx.accounts.oft_config.endpoint_program,
            ctx.remaining_accounts,
            EndpointQuoteParams {
                sender: ctx.accounts.oft_config.key(),
                dst_eid: params.dst_eid,
                receiver: ctx.accounts.peer.address,
                message: msg_codec::encode(
                    params.to,
                    u64::default(),
                    Pubkey::default(),
                    &params.compose_msg,
                ),
                pay_in_lz_token: params.pay_in_lz_token,
                options: ctx
                    .accounts
                    .enforced_options
                    .combine_options(&params.compose_msg, &params.options)?,
            },
        )
    }
}

pub fn get_post_fee_amount_ld(
    oft_type: &OftConfigExt,
    token_mint: &InterfaceAccount<anchor_spl::token_interface::Mint>,
    amount_ld: u64,
) -> Result<u64> {
    match oft_type {
        OftConfigExt::Adapter(_) => {
            let token_mint_info = token_mint.to_account_info();
            let token_mint_data = token_mint_info.try_borrow_data()?;
            let token_mint_unpacked = StateWithExtensions::<Mint>::unpack(&token_mint_data)?;
            Ok(
                if let Ok(transfer_fee_config) =
                    token_mint_unpacked.get_extension::<TransferFeeConfig>()
                {
                    transfer_fee_config
                        .get_epoch_fee(Clock::get()?.epoch)
                        .calculate_post_fee_amount(amount_ld)
                        .ok_or(ProgramError::InvalidArgument)?
                } else {
                    amount_ld
                },
            )
        },
        OftConfigExt::Native(_) => {
            return Ok(amount_ld);
        },
    }
}

// Calculate the amount_sent_ld necessary to receive amount_received_ld
// Does *not* de-dust any inputs or outputs.
pub fn get_pre_fee_amount_ld(
    oft_type: &OftConfigExt,
    token_mint: &InterfaceAccount<anchor_spl::token_interface::Mint>,
    amount_ld: u64,
) -> Result<u64> {
    match oft_type {
        OftConfigExt::Adapter(_) => {
            let token_mint_info = token_mint.to_account_info();
            let token_mint_data = token_mint_info.try_borrow_data()?;
            let token_mint_unpacked = StateWithExtensions::<Mint>::unpack(&token_mint_data)?;
            Ok(if let Ok(transfer_fee) = token_mint_unpacked.get_extension::<TransferFeeConfig>() {
                calculate_pre_fee_amount(transfer_fee.get_epoch_fee(Clock::get()?.epoch), amount_ld)
                    .ok_or(ProgramError::InvalidArgument)?
            } else {
                amount_ld
            })
        },
        OftConfigExt::Native(_) => {
            return Ok(amount_ld);
        },
    }
}

// bug reported on token2022: https://github.com/solana-labs/solana-program-library/pull/6704/files
// copy code over as fix has not been published
pub const MAX_FEE_BASIS_POINTS: u16 = 10_000;
const ONE_IN_BASIS_POINTS: u128 = MAX_FEE_BASIS_POINTS as u128;
fn calculate_pre_fee_amount(fee: &TransferFee, post_fee_amount: u64) -> Option<u64> {
    let maximum_fee = u64::from(fee.maximum_fee);
    let transfer_fee_basis_points = u16::from(fee.transfer_fee_basis_points) as u128;
    match (transfer_fee_basis_points, post_fee_amount) {
        // no fee, same amount
        (0, _) => Some(post_fee_amount),
        // 0 zero out, 0 in
        (_, 0) => Some(0),
        // 100%, cap at max fee
        (ONE_IN_BASIS_POINTS, _) => maximum_fee.checked_add(post_fee_amount),
        _ => {
            let numerator = (post_fee_amount as u128).checked_mul(ONE_IN_BASIS_POINTS)?;
            let denominator = ONE_IN_BASIS_POINTS.checked_sub(transfer_fee_basis_points)?;
            let raw_pre_fee_amount = ceil_div(numerator, denominator)?;

            if raw_pre_fee_amount.checked_sub(post_fee_amount as u128)? >= maximum_fee as u128 {
                post_fee_amount.checked_add(maximum_fee)
            } else {
                // should return `None` if `pre_fee_amount` overflows
                u64::try_from(raw_pre_fee_amount).ok()
            }
        },
    }
}

fn ceil_div(numerator: u128, denominator: u128) -> Option<u128> {
    numerator.checked_add(denominator)?.checked_sub(1)?.checked_div(denominator)
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteParams {
    pub dst_eid: u32,
    pub to: [u8; 32],
    pub amount_ld: u64,
    pub min_amount_ld: u64,
    pub options: Vec<u8>,
    pub compose_msg: Option<Vec<u8>>,
    pub pay_in_lz_token: bool,
}
