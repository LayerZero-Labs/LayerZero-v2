pub mod errors;
pub mod events;
pub mod instructions;
pub mod options_codec;
pub mod state;

use anchor_lang::prelude::*;
use errors::*;
use events::*;
use instructions::*;
use options_codec::*;
use solana_helper::program_id_from_env;
use state::*;
use worker_interface::QuoteExecutorParams;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "EXECUTOR_ID",
    "6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn"
)));

const EXECUTOR_CONFIG_SEED: &[u8] = b"ExecutorConfig";

#[program]
pub mod executor {
    use super::*;

    /// --------------------------- Owner Instructions ---------------------------
    pub fn init_executor(mut ctx: Context<InitExecutor>, params: InitExecutorParams) -> Result<()> {
        InitExecutor::apply(&mut ctx, &params)
    }

    pub fn owner_set_config(
        mut ctx: Context<OwnerSetConfig>,
        params: OwnerSetConfigParams,
    ) -> Result<()> {
        OwnerSetConfig::apply(&mut ctx, &params)
    }

    /// --------------------------- Admin Instructions ---------------------------
    pub fn admin_set_config(
        mut ctx: Context<AdminSetConfig>,
        params: AdminSetConfigParams,
    ) -> Result<()> {
        AdminSetConfig::apply(&mut ctx, &params)
    }

    pub fn native_drop<'c: 'info, 'info>(
        mut ctx: Context<'_, '_, 'c, 'info, NativeDrop<'info>>,
        params: NativeDropParams,
    ) -> Result<()> {
        NativeDrop::apply(&mut ctx, &params)
    }

    pub fn execute(mut ctx: Context<Execute>, params: ExecuteParams) -> Result<()> {
        Execute::apply(&mut ctx, &params)
    }

    pub fn compose(mut ctx: Context<Compose>, params: ComposeParams) -> Result<()> {
        Compose::apply(&mut ctx, &params)
    }

    /// --------------------------- MsgLib Instructions ---------------------------
    pub fn quote_executor(ctx: Context<Quote>, params: QuoteExecutorParams) -> Result<u64> {
        Quote::apply(&ctx, &params)
    }

    pub fn executable(
        ctx: Context<Executable>,
        params: ExecutableParams,
    ) -> Result<ExecutionState> {
        Executable::apply(&ctx, &params)
    }
}
