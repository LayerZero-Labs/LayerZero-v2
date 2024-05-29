use crate::*;
use anchor_lang::solana_program;
use anchor_spl::{
    associated_token::{get_associated_token_address_with_program_id, ID as ASSOCIATED_TOKEN_ID},
    token_interface::Mint,
};
use oapp::endpoint_cpi::LzAccount;

#[derive(Accounts)]
pub struct LzReceiveTypes<'info> {
    #[account(
        seeds = [OFT_SEED, &get_oft_config_seed(&oft_config).to_bytes()],
        bump = oft_config.bump
    )]
    pub oft_config: Account<'info, OftConfig>,
    #[account(address = oft_config.token_mint)]
    pub token_mint: InterfaceAccount<'info, Mint>,
}

// account structure
// account 0 - payer (executor)
// account 1 - peer
// account 2 - oft config
// account 3 - token escrow (optional)
// account 4 - to address / wallet address
// account 5 - token dest
// account 6 - token mint
// account 7 - token program
// account 8 - associated token program
// account 9 - system program
// account 10 - event authority
// account 11 - this program
// account remaining accounts
//  0..9 - accounts for clear
//  9..16 - accounts for compose
impl LzReceiveTypes<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypes>,
        params: &LzReceiveParams,
    ) -> Result<Vec<LzAccount>> {
        let oft = &ctx.accounts.oft_config;

        let (peer, _) = Pubkey::find_program_address(
            &[PEER_SEED, &oft.key().to_bytes(), &params.src_eid.to_be_bytes()],
            ctx.program_id,
        );

        // account 0..1
        let mut accounts = vec![
            LzAccount { pubkey: Pubkey::default(), is_signer: true, is_writable: true }, // 0
            LzAccount { pubkey: peer, is_signer: false, is_writable: true },             // 1
        ];

        // account 2..3
        let (oft_config, _) = Pubkey::find_program_address(
            &[OFT_SEED, &get_oft_config_seed(&oft).to_bytes()],
            ctx.program_id,
        );
        let token_escrow = if let OftConfigExt::Adapter(token_escrow) = oft.ext {
            LzAccount { pubkey: token_escrow, is_signer: false, is_writable: true }
        } else {
            LzAccount { pubkey: ctx.program_id.key(), is_signer: false, is_writable: false }
        };
        accounts.extend_from_slice(&[
            LzAccount { pubkey: oft_config, is_signer: false, is_writable: false }, // 2
            token_escrow,                                                           // 3
        ]);

        // account 4..8
        let to_address = Pubkey::from(msg_codec::send_to(&params.message));
        let token_dest = get_associated_token_address_with_program_id(
            &to_address,
            &ctx.accounts.oft_config.token_mint,
            &ctx.accounts.oft_config.token_program,
        );
        accounts.extend_from_slice(&[
            LzAccount { pubkey: to_address, is_signer: false, is_writable: false }, // 4
            LzAccount { pubkey: token_dest, is_signer: false, is_writable: true },  // 5
            LzAccount { pubkey: oft.token_mint, is_signer: false, is_writable: true }, // 6
            LzAccount { pubkey: oft.token_program, is_signer: false, is_writable: false }, // 7
            LzAccount { pubkey: ASSOCIATED_TOKEN_ID, is_signer: false, is_writable: false }, // 8
        ]);

        // account 9..11
        let (event_authority_account, _) =
            Pubkey::find_program_address(&[oapp::endpoint_cpi::EVENT_SEED], &ctx.program_id);
        accounts.extend_from_slice(&[
            LzAccount {
                pubkey: solana_program::system_program::ID,
                is_signer: false,
                is_writable: false,
            }, // 9
            LzAccount { pubkey: event_authority_account, is_signer: false, is_writable: false }, // 10
            LzAccount { pubkey: ctx.program_id.key(), is_signer: false, is_writable: false }, // 11
        ]);

        let endpoint_program = ctx.accounts.oft_config.endpoint_program;
        // remaining accounts 0..9
        let accounts_for_clear = oapp::endpoint_cpi::get_accounts_for_clear(
            endpoint_program,
            &oft.key(),
            params.src_eid,
            &params.sender,
            params.nonce,
        );
        accounts.extend(accounts_for_clear);

        // remaining accounts 9..16
        if let Some(message) = msg_codec::compose_msg(&params.message) {
            let amount_sd = msg_codec::amount_sd(&params.message);
            let amount_ld = ctx.accounts.oft_config.sd2ld(amount_sd);
            let amount_received_ld = get_post_fee_amount_ld(
                &ctx.accounts.oft_config.ext,
                &ctx.accounts.token_mint,
                amount_ld,
            )?;

            let accounts_for_composing = oapp::endpoint_cpi::get_accounts_for_send_compose(
                endpoint_program,
                &oft.key(),
                &to_address,
                &params.guid,
                0,
                &compose_msg_codec::encode(
                    params.nonce,
                    params.src_eid,
                    amount_received_ld,
                    &message,
                ),
            );
            accounts.extend(accounts_for_composing);
        }

        Ok(accounts)
    }
}
