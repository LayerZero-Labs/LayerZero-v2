use crate::*;

#[derive(Accounts)]
#[instruction(params: SetEnforcedOptionsParams)]
pub struct SetEnforcedOptions<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        init_if_needed,
        payer = admin,
        space = 8 + EnforcedOptions::INIT_SPACE,
        seeds = [ENFORCED_OPTIONS_SEED, &oft_config.key().to_bytes(), &params.dst_eid.to_be_bytes()],
        bump
    )]
    pub enforced_options: Account<'info, EnforcedOptions>,
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump,
        has_one = admin @OftError::Unauthorized
    )]
    pub oft_config: Account<'info, OftConfig>,
    pub system_program: Program<'info, System>,
}

impl SetEnforcedOptions<'_> {
    pub fn apply(
        ctx: &mut Context<SetEnforcedOptions>,
        params: &SetEnforcedOptionsParams,
    ) -> Result<()> {
        oapp::options::assert_type_3(&params.send)?;
        ctx.accounts.enforced_options.send = params.send.clone();
        oapp::options::assert_type_3(&params.send_and_call)?;
        ctx.accounts.enforced_options.send_and_call = params.send_and_call.clone();
        ctx.accounts.enforced_options.bump = ctx.bumps.enforced_options;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetEnforcedOptionsParams {
    pub dst_eid: u32,
    pub send: Vec<u8>,
    pub send_and_call: Vec<u8>,
}
