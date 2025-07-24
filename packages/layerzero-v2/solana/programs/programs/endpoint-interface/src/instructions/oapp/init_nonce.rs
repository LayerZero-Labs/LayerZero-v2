use crate::*;

#[derive(Accounts)]
#[instruction(params: InitNonceParams)]
pub struct InitNonce<'info> {
    /// only the delegate can initialize the nonce accounts
    #[account(mut)]
    pub delegate: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.local_oapp.as_ref()],
        bump = oapp_registry.bump,
        has_one = delegate
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        init,
        payer = delegate,
        space = 8 + Nonce::INIT_SPACE,
        seeds = [
            NONCE_SEED,
            &params.local_oapp.to_bytes(),
            &params.remote_eid.to_be_bytes(),
            &params.remote_oapp[..],
        ],
        bump
    )]
    pub nonce: Account<'info, Nonce>,
    #[account(
        init,
        payer = delegate,
        space = 8 + PendingInboundNonce::INIT_SPACE,
        seeds = [
            PENDING_NONCE_SEED,
            &params.local_oapp.to_bytes(),
            &params.remote_eid.to_be_bytes(),
            &params.remote_oapp[..],
        ],
        bump
    )]
    pub pending_inbound_nonce: Account<'info, PendingInboundNonce>,
    pub system_program: Program<'info, System>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitNonceParams {
    local_oapp: Pubkey, // the PDA of the OApp
    remote_eid: u32,
    remote_oapp: [u8; 32],
}
