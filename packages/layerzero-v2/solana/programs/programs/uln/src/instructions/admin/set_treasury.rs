use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct SetTreasury<'info> {
    /// The admin or treasury admin
    pub signer: Signer<'info>,
    #[account(mut, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
}

impl SetTreasury<'_> {
    pub fn apply(ctx: &mut Context<SetTreasury>, params: &SetTreasuryParams) -> Result<()> {
        // The signer must be the admin or the treasury admin
        let signer = ctx.accounts.signer.key();
        if signer != ctx.accounts.uln.admin {
            let treasury = ctx.accounts.uln.treasury.as_ref().ok_or(UlnError::Unauthorized)?;
            require!(Some(signer) == treasury.admin, UlnError::Unauthorized);
        }

        if let Some(param) = &params.treasury {
            require!(param.native_fee_bps <= BPS_DENOMINATOR, UlnError::InvalidBps);
        }
        ctx.accounts.uln.treasury = params.treasury.clone();

        emit_cpi!(TreasurySetEvent { treasury: params.treasury.clone() });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetTreasuryParams {
    pub treasury: Option<Treasury>,
}
