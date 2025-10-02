use crate::*;
use std::str::FromStr;

use anchor_lang::{
    prelude::*,
    solana_program::{
        serialize_utils::read_u16,
        sysvar::instructions::{load_current_index_checked, load_instruction_at_checked},
    },
    Discriminator,
};
use oapp::common::EXECUTION_CONTEXT_SEED;

// Constants for well-known program IDs
const COMPUTE_BUDGET_PROGRAM_ID: &str = "ComputeBudget111111111111111111111111111111";

#[derive(Accounts)]
#[instruction(params: PreExecuteParams)]
pub struct PreExecute<'info> {
    #[account(mut)]
    pub executor: Signer<'info>,

    /// Execution context account that stores state between pre and post execution.
    /// This account is versioned to support future protocol upgrades.
    #[account(
        init_if_needed,
        payer = executor,
        space = 8 + ExecutionContextV1::INIT_SPACE,
        seeds = [EXECUTION_CONTEXT_SEED, executor.key().as_ref(), &[params.context_version]],
        bump,
    )]
    pub context: Account<'info, ExecutionContextV1>,

    pub system_program: Program<'info, System>,

    /// Instruction sysvar account for introspection
    /// CHECK: This is the instruction sysvar account
    pub instruction_sysvar: AccountInfo<'info>,
}

impl<'info> PreExecute<'info> {
    /// Validates the instruction sequence and initializes the execution context.
    ///
    /// This instruction must be either:
    /// 1. The first instruction in the transaction, OR
    /// 2. The second instruction, with the first being a ComputeBudget instruction
    ///
    /// The last instruction in the transaction must be PostExecute.
    pub fn apply(ctx: &mut Context<Self>, params: &PreExecuteParams) -> Result<()> {
        require!(
            ctx.accounts.context.fee_limit == 0 && ctx.accounts.context.initial_payer_balance == 0,
            ExecutorError::ContextAccountAlreadyInitialized
        );

        // Validate instruction positioning
        Self::validate_instruction_sequence(&ctx.accounts.instruction_sysvar)?;

        // Ensure the transaction ends with PostExecute
        Self::validate_post_execute_exists(&ctx.accounts.instruction_sysvar)?;

        // Initialize execution context
        Self::initialize_context(&mut ctx.accounts.context, &ctx.accounts.executor, params);

        Ok(())
    }

    /// Validates that PreExecute is positioned correctly in the instruction sequence.
    fn validate_instruction_sequence(instruction_sysvar: &AccountInfo) -> Result<()> {
        let current_index = load_current_index_checked(instruction_sysvar)?;
        let compute_budget_pubkey = Pubkey::from_str(COMPUTE_BUDGET_PROGRAM_ID).unwrap();

        match current_index {
            0 => {
                // PreExecute is the first instruction - this is valid
                Ok(())
            },
            1 => {
                // PreExecute is the second instruction - verify first is ComputeBudget
                let first_instruction = load_instruction_at_checked(0, instruction_sysvar)?;
                require!(
                    first_instruction.program_id == compute_budget_pubkey,
                    ExecutorError::InvalidInstructionSequence
                );
                Ok(())
            },
            2 => {
                // PreExecute is the third instruction - verify first two are ComputeBudget
                let first_instruction = load_instruction_at_checked(0, instruction_sysvar)?;
                let second_instruction = load_instruction_at_checked(1, instruction_sysvar)?;

                require!(
                    first_instruction.program_id == compute_budget_pubkey
                        && second_instruction.program_id == compute_budget_pubkey,
                    ExecutorError::InvalidInstructionSequence
                );
                Ok(())
            },
            _ => {
                // PreExecute must be first, second, or third instruction (with ComputeBudget preceding)
                Err(error!(ExecutorError::InvalidInstructionSequence))
            },
        }
    }

    /// Validates that the last instruction in the transaction is PostExecute.
    fn validate_post_execute_exists(instruction_sysvar: &AccountInfo) -> Result<()> {
        let last_index = get_instruction_count(instruction_sysvar)? - 1;

        let last_instruction = load_instruction_at_checked(last_index.into(), instruction_sysvar)?;

        require!(
            last_instruction.program_id == ID
                && last_instruction.data.starts_with(&instruction::PostExecute::discriminator()),
            ExecutorError::InvalidInstructionSequence
        );

        Ok(())
    }

    /// Initializes the execution context with the current state.
    fn initialize_context(
        context: &mut Account<ExecutionContextV1>,
        executor: &Signer,
        params: &PreExecuteParams,
    ) {
        context.initial_payer_balance = executor.lamports();
        context.fee_limit = params.fee_limit;
    }
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct PreExecuteParams {
    /// Version of the execution context to use
    pub context_version: u8,
    /// Maximum fee that can be charged for execution
    pub fee_limit: u64,
}

/// Gets the total number of instructions in the current transaction.
///
/// # Arguments
/// * `instruction_sysvar` - The instruction sysvar account
///
/// # Returns
/// The number of instructions in the transaction
pub fn get_instruction_count(instruction_sysvar: &AccountInfo) -> Result<u16> {
    let mut cursor = 0;
    let instruction_data = instruction_sysvar.try_borrow_data()?;

    read_u16(&mut cursor, &instruction_data).map_err(|_| error!(ExecutorError::InvalidSize))
}
