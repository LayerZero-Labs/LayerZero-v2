use crate::*;

#[derive(Accounts)]
pub struct SetMintAuthority<'info> {
    /// The admin or the mint authority
    pub signer: Signer<'info>,
    #[account(
        mut,
        seeds = [OFT_SEED, oft_config.token_mint.as_ref()],
        bump = oft_config.bump,
        constraint = is_valid_signer(signer.key(), &oft_config) @OftError::Unauthorized
    )]
    pub oft_config: Account<'info, OftConfig>,
}

impl SetMintAuthority<'_> {
    pub fn apply(
        ctx: &mut Context<SetMintAuthority>,
        params: &SetMintAuthorityParams,
    ) -> Result<()> {
        // the mint authority can be removed by setting it to None
        ctx.accounts.oft_config.ext = OftConfigExt::Native(params.mint_authority);
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetMintAuthorityParams {
    pub mint_authority: Option<Pubkey>,
}

/// Check if the signer is the admin or the mint authority
/// When the mint authority is set, the signer can be the admin or the mint authority
/// Otherwise, no one can set the mint authority
fn is_valid_signer(signer: Pubkey, oft_config: &OftConfig) -> bool {
    if let OftConfigExt::Native(Some(mint_authority)) = oft_config.ext {
        signer == oft_config.admin || signer == mint_authority
    } else {
        false
    }
}
