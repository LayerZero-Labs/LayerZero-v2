use crate::*;
use anchor_spl::token_interface::{Mint, TokenAccount, TokenInterface};

#[derive(Accounts)]
#[instruction(params: InitAdapterOftParams)]
pub struct InitAdapterOft<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + OftConfig::INIT_SPACE,
        seeds = [OFT_SEED, token_escrow.key().as_ref()],
        bump
    )]
    pub oft_config: Account<'info, OftConfig>,
    #[account(
        init,
        payer = payer,
        space = 8 + LzReceiveTypesAccounts::INIT_SPACE,
        seeds = [LZ_RECEIVE_TYPES_SEED, &oft_config.key().as_ref()],
        bump
    )]
    pub lz_receive_types_accounts: Account<'info, LzReceiveTypesAccounts>,
    #[account(mint::token_program = token_program)]
    pub token_mint: InterfaceAccount<'info, Mint>,
    #[account(
        init,
        payer = payer,
        token::authority = oft_config,
        token::mint = token_mint,
        token::token_program = token_program,
    )]
    pub token_escrow: InterfaceAccount<'info, TokenAccount>,
    pub token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

impl InitAdapterOft<'_> {
    pub fn apply(ctx: &mut Context<InitAdapterOft>, params: &InitAdapterOftParams) -> Result<()> {
        ctx.accounts.oft_config.bump = ctx.bumps.oft_config;
        ctx.accounts.oft_config.token_mint = ctx.accounts.token_mint.key();
        ctx.accounts.oft_config.ext = OftConfigExt::Adapter(ctx.accounts.token_escrow.key());
        ctx.accounts.oft_config.token_program = ctx.accounts.token_program.key();

        ctx.accounts.lz_receive_types_accounts.oft_config = ctx.accounts.oft_config.key();
        ctx.accounts.lz_receive_types_accounts.token_mint = ctx.accounts.token_mint.key();

        let oapp_signer = ctx.accounts.oft_config.key();
        ctx.accounts.oft_config.init(
            params.endpoint_program,
            params.admin,
            params.shared_decimals,
            ctx.accounts.token_mint.decimals,
            ctx.remaining_accounts,
            oapp_signer,
        )
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitAdapterOftParams {
    pub admin: Pubkey,
    pub shared_decimals: u8,
    pub endpoint_program: Option<Pubkey>,
}
