use crate::*;
use messagelib_helper::{
    endpoint::instructions::hash_payload, packet_v1_codec::encode_packet_header,
};
use worker_interface::{LzOption, QuoteDvnParams, QuoteExecutorParams};

#[derive(Accounts)]
#[instruction(params: QuoteParams)]
pub struct Quote<'info> {
    pub endpoint: Signer<'info>,
    #[account(seeds = [ULN_SEED], bump = uln.bump, has_one = endpoint)]
    pub uln: Account<'info, UlnSettings>,
    /// The custom send config account may be uninitialized, so deserialize it only if it's initialized
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes(), &params.packet.sender.to_bytes()],
        bump
    )]
    pub send_config: AccountInfo<'info>,
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes()],
        bump = default_send_config.bump,
    )]
    pub default_send_config: Account<'info, SendConfig>,
}

impl Quote<'_> {
    pub fn apply(ctx: &Context<Quote>, params: &QuoteParams) -> Result<MessagingFee> {
        let (uln_config, executor_config) =
            get_send_config(&ctx.accounts.send_config, &ctx.accounts.default_send_config)?;

        let (executor_options, dvn_options) = decode_options(&params.options)?;

        // executor fee
        let executor_fee = quote_executor(
            &ctx.accounts.uln.key(),
            &executor_config,
            params.packet.dst_eid,
            &params.packet.sender,
            params.packet.message.len() as u64,
            executor_options,
            &ctx.remaining_accounts[0..4],
        )?;

        // dvn fees
        let dvn_fees = quote_dvns(
            &ctx.accounts.uln.key(),
            &uln_config,
            params.packet.dst_eid,
            &params.packet.sender,
            encode_packet_header(&params.packet),
            hash_payload(&params.packet.guid, &params.packet.message),
            dvn_options,
            &ctx.remaining_accounts[4..],
        )?;

        let worker_fee = executor_fee.fee + dvn_fees.iter().map(|f| f.fee).sum::<u64>();

        let (native_fee, lz_token_fee) = if let Some(treasury) = ctx.accounts.uln.treasury.as_ref()
        {
            let treasury_fee = quote_treasury(treasury, worker_fee, params.pay_in_lz_token)?;

            if params.pay_in_lz_token {
                (worker_fee, treasury_fee)
            } else {
                (worker_fee + treasury_fee, 0)
            }
        } else {
            (worker_fee, 0)
        };

        Ok(MessagingFee { native_fee, lz_token_fee })
    }
}

pub fn quote_executor(
    uln: &Pubkey,
    executor_config: &ExecutorConfig,
    dst_eid: u32,
    sender: &Pubkey,
    calldata_size: u64,
    options: Vec<LzOption>,
    // [executor_program, executor_config, price_feed_program, price_feed_config]
    accounts: &[AccountInfo],
) -> Result<WorkerFee> {
    require!(
        calldata_size <= executor_config.max_message_size as u64,
        UlnError::ExceededMaxMessageSize
    );

    // assert all accounts are non-signer
    // executor_config should be writable to receive the fee on send(), so it's not checked
    for account in accounts {
        require!(!account.is_signer, UlnError::NonSigner);
    }

    let executor_program = &accounts[0];
    let executor_acc = &accounts[1];
    // assert executor program is owner of executor config
    require!(executor_program.key() == *executor_acc.owner, UlnError::InvalidExecutorProgram);
    // assert executor is the same as the executor in the executor config
    require!(executor_config.executor == executor_acc.key(), UlnError::InvalidExecutor);

    let params =
        QuoteExecutorParams { msglib: uln.key(), dst_eid, sender: *sender, calldata_size, options };
    let cpi_ctx = CpiContext::new(
        executor_program.to_account_info(),
        worker_interface::cpi::accounts::Quote {
            worker_config: executor_acc.to_account_info(),
            price_feed_program: accounts[2].to_account_info(),
            price_feed_config: accounts[3].to_account_info(),
        },
    );
    let fee = worker_interface::cpi::quote_executor(cpi_ctx, params)?.get();
    Ok(WorkerFee { worker: executor_config.executor, fee })
}

pub fn quote_dvns(
    uln: &Pubkey,
    uln_config: &UlnConfig,
    dst_eid: u32,
    sender: &Pubkey,
    packet_header: Vec<u8>,
    payload_hash: [u8; 32],
    options: DVNOptions,
    // [dvn_program, dvn_config, price_feed_program, price_feed_config, ...]
    accounts: &[AccountInfo],
) -> Result<Vec<WorkerFee>> {
    let length = uln_config.required_dvns.len() + uln_config.optional_dvns.len();
    require!(accounts.len() == length * 4, UlnError::InvalidAccountLength);

    // assert all accounts are non-signer
    // dvn_config should be writable to receive the fee on send(), so it's not checked
    for account in accounts {
        require!(!account.is_signer, UlnError::NonSigner);
    }

    let mut fees = Vec::with_capacity(length);
    for (i, chunk) in accounts.chunks(4).enumerate() {
        let dvn_program = &chunk[0];
        let dvn_acc = &chunk[1];
        // assert dvn program is owner of dvn config
        require!(dvn_program.key() == *dvn_acc.owner, UlnError::InvalidDvnProgram);
        let dvn = if i < uln_config.required_dvns.len() {
            uln_config.required_dvns[i]
        } else {
            uln_config.optional_dvns[i - uln_config.required_dvns.len()]
        };
        // assert dvn is the same as the dvn in the dvn config
        require!(dvn == dvn_acc.key(), UlnError::InvalidDvn);

        let options = options.get(&(i as u8)).cloned().unwrap_or_default();
        let params = QuoteDvnParams {
            msglib: uln.key(),
            dst_eid,
            sender: *sender,
            packet_header: packet_header.clone(),
            payload_hash,
            confirmations: uln_config.confirmations,
            options,
        };
        let cpi_ctx = CpiContext::new(
            dvn_program.to_account_info(),
            worker_interface::cpi::accounts::Quote {
                worker_config: dvn_acc.to_account_info(),
                price_feed_program: chunk[2].to_account_info(),
                price_feed_config: chunk[3].to_account_info(),
            },
        );
        let fee = worker_interface::cpi::quote_dvn(cpi_ctx, params)?.get();
        fees.push(WorkerFee { worker: dvn, fee });
    }
    Ok(fees)
}

pub(crate) fn quote_treasury(
    treasury: &Treasury,
    worker_fee: u64,
    pay_in_lz_token: bool,
) -> Result<u64> {
    if pay_in_lz_token {
        let treasury = treasury.lz_token.as_ref().ok_or(UlnError::LzTokenUnavailable)?;
        Ok(treasury.fee)
    } else {
        // pay in native
        Ok(worker_fee * treasury.native_fee_bps / BPS_DENOMINATOR)
    }
}
