use crate::*;
use anchor_spl::token_interface::{Mint, TokenInterface};

/// This instruction should always be in the same transaction as InitializeMint.
/// Otherwise, it is possible for your settings to be front-run by another transaction.
/// If such a case did happen, you should initialize another mint for this oft.
#[derive(Accounts)]
#[instruction(params: InitOftParams)]
pub struct InitOft<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + OftConfig::INIT_SPACE,
        seeds = [OFT_SEED, token_mint.key().as_ref()],
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
    #[account(
        mint::authority = oft_config,
        mint::token_program = token_program
    )]
    pub token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

impl InitOft<'_> {
    pub fn apply(ctx: &mut Context<InitOft>, params: &InitOftParams) -> Result<()> {
        ctx.accounts.oft_config.bump = ctx.bumps.oft_config;
        ctx.accounts.oft_config.token_mint = ctx.accounts.token_mint.key();
        ctx.accounts.oft_config.ext = OftConfigExt::Native(params.mint_authority);
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
pub struct InitOftParams {
    pub admin: Pubkey,
    pub shared_decimals: u8,
    pub endpoint_program: Option<Pubkey>,
    pub mint_authority: Option<Pubkey>,
}
