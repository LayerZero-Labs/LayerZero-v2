use crate::*;
use anchor_lang::solana_program::{program, system_instruction};

#[event_cpi]
#[derive(Accounts)]
pub struct NativeDrop<'info> {
    #[account(mut)]
    pub executor: Signer<'info>,
    #[account(
        mut,
        seeds = [EXECUTOR_CONFIG_SEED],
        bump = config.bump,
        constraint = config.executors.contains(executor.key) @ExecutorError::NotExecutor
    )]
    pub config: Account<'info, ExecutorConfig>,
    /// For native drop transfer
    pub system_program: Program<'info, System>,
}

impl NativeDrop<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &mut Context<'_, '_, 'c, 'info, NativeDrop<'info>>,
        params: &NativeDropParams,
    ) -> Result<()> {
        require!(
            ctx.remaining_accounts.len() == params.native_drop_requests.len(),
            ExecutorError::InvalidNativeDropRequestsLength
        );

        let mut successes: Vec<bool> = vec![];
        for (index, request) in params.native_drop_requests.iter().enumerate() {
            let receiver_account_info = ctx.remaining_accounts[index].to_account_info();
            require!(
                receiver_account_info.key() == request.receiver,
                ExecutorError::InvalidNativeDropReceiver
            );

            let success = program::invoke(
                &system_instruction::transfer(
                    ctx.accounts.executor.key,
                    &request.receiver.key(),
                    request.amount,
                ),
                &[ctx.accounts.executor.to_account_info(), receiver_account_info.to_account_info()],
            )
            .is_ok();
            successes.push(success);
        }

        emit_cpi!(NativeDropAppliedEvent {
            dst_eid: params.dst_eid,
            oapp: params.oapp,
            native_drop_requests: params.native_drop_requests.clone(),
            successes,
            nonce: params.nonce,
            sender: params.sender,
            src_eid: params.src_eid,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct NativeDropParams {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub dst_eid: u32,
    pub oapp: Pubkey,
    pub native_drop_requests: Vec<NativeDropRequest>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct NativeDropRequest {
    pub receiver: Pubkey,
    pub amount: u64,
}
