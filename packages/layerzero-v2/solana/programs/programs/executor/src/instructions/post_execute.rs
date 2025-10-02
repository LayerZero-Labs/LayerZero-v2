use crate::*;
use anchor_lang::{
    prelude::*,
    solana_program::{
        system_program,
        sysvar::instructions::{load_current_index_checked, load_instruction_at_checked},
    },
    Discriminator,
};

use oapp::common::EXECUTION_CONTEXT_SEED;

use super::pre_execute::get_instruction_count;

#[derive(Accounts)]
#[instruction(params: PostExecuteParams)]
pub struct PostExecute<'info> {
    pub executor: Signer<'info>,

    /// Execution context account containing state from pre-execution
    #[account(
        mut,
        seeds = [EXECUTION_CONTEXT_SEED, executor.key().as_ref(), &[params.context_version]],
        bump
    )]
    pub context: Account<'info, ExecutionContextV1>,

    /// Instruction sysvar account for introspection
    /// CHECK: This is the instruction sysvar account
    pub instruction_sysvar: AccountInfo<'info>,
}

impl<'info> PostExecute<'info> {
    /// Validates the execution context and ensures fee limits are respected.
    ///
    /// This instruction must be the last in the transaction and must be paired
    /// with a corresponding PreExecute instruction.
    pub fn apply(ctx: &mut Context<Self>, _params: &PostExecuteParams) -> Result<()> {
        // Validate instruction positioning and pairing
        Self::validate_instruction_pairing(&ctx.accounts.instruction_sysvar)?;

        // Validate execution position (must be last instruction)
        Self::validate_execution_position(&ctx.accounts.instruction_sysvar)?;

        // Validate fee limits and executor state
        Self::validate_fee_limits_and_executor_state(
            &ctx.accounts.executor,
            &ctx.accounts.context,
        )?;

        // Reset the execution context
        Self::reset_execution_context(&mut ctx.accounts.context);

        Ok(())
    }

    /// Validates that this PostExecute instruction is properly paired with a PreExecute instruction.
    /// This ensures the execution bracket is properly formed for fee tracking.
    fn validate_instruction_pairing(instruction_sysvar: &AccountInfo) -> Result<()> {
        // Check index 0 first (most common case - PreExecute is the first instruction)
        if let Ok(instruction_at_0) = load_instruction_at_checked(0, instruction_sysvar) {
            if Self::is_pre_execute_instruction(&instruction_at_0) {
                return Ok(());
            }
        }

        // If not found at index 0, check index 1 (accounting for optional ComputeBudget at index 0)
        if let Ok(instruction_at_1) = load_instruction_at_checked(1, instruction_sysvar) {
            if Self::is_pre_execute_instruction(&instruction_at_1) {
                return Ok(());
            }
        }

        // If not found at index 1, check index 2 (accounting for two ComputeBudget instructions)
        // Some transactions may include two ComputeBudget instructions (compute unit and unit price) before PreExecute
        let instruction_at_2 = load_instruction_at_checked(2, instruction_sysvar)?;
        require!(
            Self::is_pre_execute_instruction(&instruction_at_2),
            ExecutorError::InvalidInstructionSequence
        );

        Ok(())
    }

    /// Validates that PostExecute is the last instruction in the transaction.
    fn validate_execution_position(instruction_sysvar: &AccountInfo) -> Result<()> {
        let current_index = load_current_index_checked(instruction_sysvar)?;
        let last_index = get_instruction_count(instruction_sysvar)? - 1;

        require!(current_index == last_index, ExecutorError::InvalidInstructionSequence);

        Ok(())
    }

    /// Validates fee limits and executor account state.
    fn validate_fee_limits_and_executor_state(
        executor: &Signer,
        context: &Account<ExecutionContextV1>,
    ) -> Result<()> {
        // Validate fee limits
        let balance_after = executor.lamports();
        let balance_before = context.initial_payer_balance;
        let fee_limit = context.fee_limit;

        require!(balance_before <= balance_after + fee_limit, ExecutorError::InsufficientBalance);

        // Validate executor account state
        require!(executor.owner.key() == system_program::ID, ExecutorError::InvalidOwner);

        require!(executor.data_is_empty(), ExecutorError::InvalidSize);

        Ok(())
    }

    /// Resets the execution context to its initial state.
    /// This clears the fee tracking data after successful execution validation.
    fn reset_execution_context(context: &mut Account<ExecutionContextV1>) {
        context.initial_payer_balance = 0;
        context.fee_limit = 0;
    }

    /// Checks if the given instruction is a PreExecute instruction.
    fn is_pre_execute_instruction(
        instruction: &anchor_lang::solana_program::instruction::Instruction,
    ) -> bool {
        instruction.program_id == ID
            && instruction.data.starts_with(&instruction::PreExecute::discriminator())
    }
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct PostExecuteParams {
    /// Version of the execution context to use
    pub context_version: u8,
}
