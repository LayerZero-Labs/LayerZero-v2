use crate::*;

use anchor_spl::token_interface::{
    self, Mint, MintTo as TokenMintTo, TokenAccount, TokenInterface,
};

#[derive(Accounts)]
pub struct MintTo<'info> {
    pub minter: Signer<'info>,
    /// only the non-adapter oft can mint token to the destination account
    #[account(
        seeds = [OFT_SEED, oft_config.token_mint.as_ref()],
        bump = oft_config.bump,
        constraint = oft_config.ext == OftConfigExt::Native(Some(minter.key())) @OftError::Unauthorized
    )]
    pub oft_config: Account<'info, OftConfig>,
    #[account(
        mut,
        token::mint = token_mint,
        token::token_program = token_program,
    )]
    pub token_dest: InterfaceAccount<'info, TokenAccount>,
    #[account(mut, address = oft_config.token_mint)]
    pub token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
}

impl MintTo<'_> {
    pub fn apply(ctx: &mut Context<MintTo>, params: &MintToParams) -> Result<()> {
        token_interface::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                TokenMintTo {
                    mint: ctx.accounts.token_mint.to_account_info(),
                    to: ctx.accounts.token_dest.to_account_info(),
                    authority: ctx.accounts.oft_config.to_account_info(),
                },
                &[&[
                    OFT_SEED,
                    ctx.accounts.oft_config.token_mint.as_ref(),
                    &[ctx.accounts.oft_config.bump],
                ]],
            ),
            params.amount,
        )?;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct MintToParams {
    pub amount: u64,
}
