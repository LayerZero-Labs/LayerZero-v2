use crate::*;

#[derive(Accounts)]
pub struct OwnerSetConfig<'info> {
    pub owner: Signer<'info>,
    #[account(mut, seeds = [EXECUTOR_CONFIG_SEED], bump = config.bump, has_one = owner)]
    pub config: Account<'info, ExecutorConfig>,
}

impl OwnerSetConfig<'_> {
    pub fn apply(ctx: &mut Context<OwnerSetConfig>, params: &OwnerSetConfigParams) -> Result<()> {
        params.apply(&mut ctx.accounts.config)?;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum OwnerSetConfigParams {
    Admins(Vec<Pubkey>),
    Executors(Vec<Pubkey>),
    Msglibs(Vec<Pubkey>),
    Owner(Pubkey),
    Paused(bool),
    Allowlist(Vec<Pubkey>),
    Denylist(Vec<Pubkey>),
}

impl OwnerSetConfigParams {
    pub fn apply(&self, config: &mut ExecutorConfig) -> Result<()> {
        match self {
            Self::Admins(admins) => config.set_admins(admins.clone()),
            Self::Executors(executors) => config.set_executors(executors.clone()),
            Self::Msglibs(msglibs) => config.set_msglibs(msglibs.clone()),
            Self::Owner(owner) => {
                config.owner = *owner;
                Ok(())
            },
            Self::Paused(paused) => {
                config.paused = *paused;
                Ok(())
            },
            Self::Allowlist(allowlist) => {
                for addr in allowlist {
                    config.acl.set_allowlist(addr)?;
                }
                Ok(())
            },
            Self::Denylist(denylist) => {
                for addr in denylist {
                    config.acl.set_denylist(addr)?;
                }
                Ok(())
            },
        }
    }
}
