use crate::*;
use anchor_lang::solana_program::{instruction::Instruction, program::invoke, system_program};
use oapp::{
    endpoint::{
        self, cpi::accounts::LzComposeAlert, instructions::LzComposeAlertParams, program::Endpoint,
        ConstructCPIContext,
    },
    LzComposeParams,
};

pub const LZ_COMPOSE_DISCRIMINATOR: [u8; 8] = [143, 252, 164, 222, 203, 105, 240, 7];

#[event_cpi]
#[derive(Accounts)]
pub struct Compose<'info> {
    #[account(mut)]
    pub executor: Signer<'info>,
    #[account(
        seeds = [EXECUTOR_CONFIG_SEED],
        bump = config.bump,
        constraint = config.executors.contains(executor.key) @ExecutorError::NotExecutor
    )]
    pub config: Account<'info, ExecutorConfig>,
    pub endpoint_program: Program<'info, Endpoint>,
    /// The authority for the endpoint program to emit events
    pub endpoint_event_authority: UncheckedAccount<'info>,
}

impl Compose<'_> {
    pub fn apply(ctx: &mut Context<Compose>, params: &ComposeParams) -> Result<()> {
        let balance_before = ctx.accounts.executor.lamports();
        let program_id = ctx.remaining_accounts[0].key();
        let accounts = ctx
            .remaining_accounts
            .iter()
            .skip(1)
            .map(|acc| acc.to_account_metas(None)[0].clone())
            .collect::<Vec<_>>();
        let data = get_lz_compose_ix_data(&params.lz_compose)?;
        let result = invoke(&Instruction { program_id, accounts, data }, ctx.remaining_accounts);

        if let Err(e) = result {
            // call lz_compose_alert
            let params = LzComposeAlertParams {
                from: params.lz_compose.from,
                to: params.lz_compose.to,
                guid: params.lz_compose.guid,
                index: params.lz_compose.index,
                compute_units: params.compute_units,
                value: params.value,
                message: params.lz_compose.message.clone(),
                extra_data: params.lz_compose.extra_data.clone(),
                reason: e.to_string().into_bytes(),
            };

            let cpi_ctx = LzComposeAlert::construct_context(
                ctx.accounts.endpoint_program.key(),
                &[
                    ctx.accounts.config.to_account_info(), // use the executor config as the signer
                    ctx.accounts.endpoint_event_authority.to_account_info(),
                    ctx.accounts.endpoint_program.to_account_info(),
                ],
            )?;
            endpoint::cpi::lz_compose_alert(
                cpi_ctx.with_signer(&[&[EXECUTOR_CONFIG_SEED, &[ctx.accounts.config.bump]]]),
                params,
            )?;
        } else {
            // assert that the executor account does not lose more than the expected value
            let balance_after = ctx.accounts.executor.lamports();
            require!(
                balance_before <= balance_after + params.value,
                ExecutorError::InsufficientBalance
            );
        }
        require!(
            ctx.accounts.executor.owner.key() == system_program::ID,
            ExecutorError::InvalidOwner
        );
        require!(ctx.accounts.executor.data_is_empty(), ExecutorError::InvalidSize);
        Ok(())
    }
}

fn get_lz_compose_ix_data(params: &LzComposeParams) -> Result<Vec<u8>> {
    let mut data = Vec::with_capacity(114 + params.message.len() + params.extra_data.len()); // 8 + 32 + 32 + 32 + 2 + 4 + 4
    data.extend(LZ_COMPOSE_DISCRIMINATOR);
    params.serialize(&mut data)?;
    Ok(data)
}

#[test]
fn lz_compose_ix_data() {
    let params = LzComposeParams {
        from: Pubkey::new_unique(),
        to: Pubkey::new_unique(),
        guid: [1; 32],
        index: 0,
        message: vec![1; 32],
        extra_data: vec![2; 32],
    };
    let data = get_lz_compose_ix_data(&params).unwrap();
    assert_eq!(data.len(), 114 + params.message.len() + params.extra_data.len());
    assert_eq!(data.len(), 8 + params.try_to_vec().unwrap().len());
    let mut expected = LZ_COMPOSE_DISCRIMINATOR.to_vec();
    expected.extend_from_slice(&params.try_to_vec().unwrap());
    assert_eq!(data, expected);
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ComposeParams {
    pub lz_compose: LzComposeParams,
    pub compute_units: u64,
    pub value: u64,
}
