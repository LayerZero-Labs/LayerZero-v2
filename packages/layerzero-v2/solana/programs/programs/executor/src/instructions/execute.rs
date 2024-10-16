use crate::*;
use anchor_lang::solana_program::{instruction::Instruction, program::invoke, system_program};
use oapp::{
    endpoint::{
        self, cpi::accounts::LzReceiveAlert, instructions::LzReceiveAlertParams, program::Endpoint,
        ConstructCPIContext,
    },
    LzReceiveParams,
};

pub const LZ_RECEIVE_DISCRIMINATOR: [u8; 8] = [8, 179, 120, 109, 33, 118, 189, 80];

#[event_cpi]
#[derive(Accounts)]
pub struct Execute<'info> {
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

impl Execute<'_> {
    pub fn apply(ctx: &mut Context<Execute>, params: &ExecuteParams) -> Result<()> {
        let balance_before = ctx.accounts.executor.lamports();
        let program_id = ctx.remaining_accounts[0].key();
        let accounts = ctx
            .remaining_accounts
            .iter()
            .skip(1)
            .map(|acc| acc.to_account_metas(None)[0].clone())
            .collect::<Vec<_>>();
        let data = get_lz_receive_ix_data(&params.lz_receive)?;
        let result = invoke(&Instruction { program_id, accounts, data }, ctx.remaining_accounts);

        if let Err(e) = result {
            // call lz_receive_alert
            let params = LzReceiveAlertParams {
                receiver: params.receiver,
                src_eid: params.lz_receive.src_eid,
                sender: params.lz_receive.sender,
                nonce: params.lz_receive.nonce,
                guid: params.lz_receive.guid,
                compute_units: params.compute_units,
                value: params.value,
                message: params.lz_receive.message.clone(),
                extra_data: params.lz_receive.extra_data.clone(),
                reason: e.to_string().into_bytes(),
            };

            let cpi_ctx = LzReceiveAlert::construct_context(
                ctx.accounts.endpoint_program.key(),
                &[
                    ctx.accounts.config.to_account_info(), // use the executor config as the signer
                    ctx.accounts.endpoint_event_authority.to_account_info(),
                    ctx.accounts.endpoint_program.to_account_info(),
                ],
            )?;
            endpoint::cpi::lz_receive_alert(
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

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ExecuteParams {
    pub receiver: Pubkey,
    pub lz_receive: LzReceiveParams,
    pub value: u64,
    pub compute_units: u64,
}

fn get_lz_receive_ix_data(params: &LzReceiveParams) -> Result<Vec<u8>> {
    let mut data = Vec::with_capacity(92 + params.message.len() + params.extra_data.len()); // 8 + 4 + 32 + 8 + 32 + 4 + 4
    data.extend(LZ_RECEIVE_DISCRIMINATOR);
    params.serialize(&mut data)?;
    Ok(data)
}

#[test]
fn lz_receive_ix_data() {
    let params = LzReceiveParams {
        src_eid: 0,
        sender: [1; 32],
        nonce: 0,
        guid: [2; 32],
        message: vec![3; 32],
        extra_data: vec![4; 32],
    };
    let data = get_lz_receive_ix_data(&params).unwrap();
    assert_eq!(data.len(), 92 + params.message.len() + params.extra_data.len());
    assert_eq!(data.len(), 8 + params.try_to_vec().unwrap().len());
    let mut expected = LZ_RECEIVE_DISCRIMINATOR.to_vec();
    expected.extend_from_slice(&params.try_to_vec().unwrap());
    assert_eq!(data, expected);
}
