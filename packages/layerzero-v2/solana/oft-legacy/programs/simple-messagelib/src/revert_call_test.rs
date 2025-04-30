use crate::*;

/// RevertCall is a test endpoint that always reverts. only used for testing.
#[derive(Accounts)]
pub struct RevertCall {}

impl RevertCall {
    pub fn apply(_ctx: &mut Context<RevertCall>) -> Result<()> {
        Err(SimpleMessageLibError::OnlyRevert.into())
    }
}
