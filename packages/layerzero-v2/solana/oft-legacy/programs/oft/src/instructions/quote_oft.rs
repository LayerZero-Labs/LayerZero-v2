use crate::*;

#[derive(Accounts)]
#[instruction(params: QuoteOftParams)]
pub struct QuoteOft<'info> {
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
        address = oft_config.token_mint,
    )]
    pub token_mint: InterfaceAccount<'info, anchor_spl::token_interface::Mint>,
}

impl QuoteOft<'_> {
    pub fn apply(ctx: &Context<QuoteOft>, params: &QuoteOftParams) -> Result<QuoteOftResult> {
        // 1. Quote the amount with token2022 fee and dedust it
        let amount_received_ld = ctx.accounts.oft_config.remove_dust(get_post_fee_amount_ld(
            &ctx.accounts.oft_config.ext,
            &ctx.accounts.token_mint,
            params.amount_ld,
        )?);
        require!(amount_received_ld >= params.min_amount_ld, OftError::SlippageExceeded);

        // amount_sent_ld does not have to be dedusted
        let amount_sent_ld = get_pre_fee_amount_ld(
            &ctx.accounts.oft_config.ext,
            &ctx.accounts.token_mint,
            amount_received_ld,
        )?;
        let oft_limits = OFTLimits { min_amount_ld: 0, max_amount_ld: 0xffffffffffffffff };
        let oft_fee_details = if amount_received_ld < amount_sent_ld {
            vec![OFTFeeDetail {
                fee_amount_ld: amount_sent_ld - amount_received_ld,
                description: "Token2022 Transfer Fee".to_string(),
            }]
        } else {
            vec![]
        };
        let oft_receipt = OFTReceipt { amount_sent_ld, amount_received_ld };
        Ok(QuoteOftResult { oft_limits, oft_fee_details, oft_receipt })
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteOftParams {
    pub dst_eid: u32,
    pub to: [u8; 32],
    pub amount_ld: u64,
    pub min_amount_ld: u64,
    pub options: Vec<u8>,
    pub compose_msg: Option<Vec<u8>>,
    pub pay_in_lz_token: bool,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteOftResult {
    pub oft_limits: OFTLimits,
    pub oft_fee_details: Vec<OFTFeeDetail>,
    pub oft_receipt: OFTReceipt,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTFeeDetail {
    pub fee_amount_ld: u64,
    pub description: String,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTReceipt {
    pub amount_sent_ld: u64,
    pub amount_received_ld: u64,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTLimits {
    pub min_amount_ld: u64,
    pub max_amount_ld: u64,
}
