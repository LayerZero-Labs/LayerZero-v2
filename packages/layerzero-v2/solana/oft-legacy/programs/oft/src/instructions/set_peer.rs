use crate::*;

#[derive(Accounts)]
#[instruction(params: SetPeerParams)]
pub struct SetPeer<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        init_if_needed,
        payer = admin,
        space = 8 + Peer::INIT_SPACE,
        seeds = [PEER_SEED, &oft_config.key().to_bytes(), &params.dst_eid.to_be_bytes()],
        bump
    )]
    pub peer: Account<'info, Peer>,
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump,
        has_one = admin @OftError::Unauthorized
    )]
    pub oft_config: Account<'info, OftConfig>,
    pub system_program: Program<'info, System>,
}

impl SetPeer<'_> {
    pub fn apply(ctx: &mut Context<SetPeer>, params: &SetPeerParams) -> Result<()> {
        ctx.accounts.peer.address = params.peer;
        ctx.accounts.peer.bump = ctx.bumps.peer;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetPeerParams {
    pub dst_eid: u32,
    pub peer: [u8; 32],
}
