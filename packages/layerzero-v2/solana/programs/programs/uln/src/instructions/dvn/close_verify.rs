use crate::*;

#[derive(Accounts)]
#[instruction(params: CloseVerifyParams)]
pub struct CloseVerify<'info> {
    pub dvn: Signer<'info>,
    #[account(mut)]
    pub receiver: AccountInfo<'info>,
    #[account(
        mut,
        seeds = [
            CONFIRMATIONS_SEED,
            &params.packet_header_hash[..],
            &params.payload_hash[..],
            dvn.key.as_ref()
        ],
        bump = confirmations.bump,
        close = receiver
    )]
    pub confirmations: Account<'info, Confirmations>,
}

impl CloseVerify<'_> {
    pub fn apply() -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct CloseVerifyParams {
    pub packet_header_hash: [u8; 32],
    pub payload_hash: [u8; 32],
}
