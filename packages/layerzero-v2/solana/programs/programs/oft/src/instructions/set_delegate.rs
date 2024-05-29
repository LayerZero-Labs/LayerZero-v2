use crate::*;
use endpoint::instructions::SetDelegateParams as EndpointSetDelegateParams;
use oapp::endpoint;

#[derive(Accounts)]
#[instruction(params: SetDelegateParams)]
pub struct SetDelegate<'info> {
    pub admin: Signer<'info>,
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump,
        has_one = admin @OftError::Unauthorized
    )]
    pub oft_config: Account<'info, OftConfig>,
}

impl SetDelegate<'_> {
    pub fn apply(ctx: &mut Context<SetDelegate>, params: &SetDelegateParams) -> Result<()> {
        let oft_config_seed = get_oft_config_seed(&ctx.accounts.oft_config);
        let seeds: &[&[u8]] =
            &[OFT_SEED, &oft_config_seed.to_bytes(), &[ctx.accounts.oft_config.bump]];
        let _ = oapp::endpoint_cpi::set_delegate(
            ctx.accounts.oft_config.endpoint_program,
            ctx.accounts.oft_config.key(),
            &ctx.remaining_accounts,
            seeds,
            EndpointSetDelegateParams { delegate: params.delegate },
        )?;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDelegateParams {
    pub delegate: Pubkey,
}
