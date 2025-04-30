extern crate proc_macro;

use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};

#[proc_macro_derive(CpiContext)]
pub fn derive_cpi_context(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;

    // Extracting fields from the struct
    let fields = match &input.data {
        syn::Data::Struct(data) => match &data.fields {
            syn::Fields::Named(fields) => {
                fields.named.iter().map(|f| f.clone()).collect::<Vec<_>>()
            },
            _ => panic!("CpiContext only supports structs with named fields."),
        },
        _ => panic!("CpiContext can only be used with structs."),
    };
    let cpi_accounts = fields.iter().map(|f| {
        let ident = f.ident.as_ref().unwrap();
        let ty = &f.ty;
        return match ty {
            syn::Type::Path(type_path) if type_path.path.segments[0].ident == "Option" => {
                quote! { #ident: acc_iter.next().map(|acc| acc.to_account_info()) }
            },
            _ => {
                quote! { #ident: acc_iter.next().unwrap().to_account_info() }
            },
        };
    });
    let field_count = fields.len();
    let min_accounts_len = field_count + 1;
    let error_handling = quote! {
        if !(accounts.len() >= #min_accounts_len) {
            return Err(anchor_lang::error::ErrorCode::AccountNotEnoughKeys.into());
        }
    };

    let output = quote! {
        #[cfg(feature = "cpi")]
        impl<'a, 'b, 'c, 'info> ConstructCPIContext<'a, 'b, 'c, 'info, crate::cpi::accounts::#name<'info>> for crate::cpi::accounts::#name<'info> {
            const MIN_ACCOUNTS_LEN: usize = #min_accounts_len;

            fn construct_context(
                program_id: solana_program::pubkey::Pubkey,
                accounts: &[solana_program::account_info::AccountInfo<'info>],
            ) -> anchor_lang::Result<anchor_lang::context::CpiContext<'a, 'b, 'c, 'info, crate::cpi::accounts::#name<'info>>> {
                if (program_id != accounts[0].key()) {
                    return Err(anchor_lang::error::ErrorCode::InvalidProgramId.into());
                }

                #error_handling
                let mut acc_iter = accounts.iter();
                let cpi_program = acc_iter.next().unwrap().to_account_info();
                let cpi_accounts = crate::cpi::accounts::#name {
                    #(#cpi_accounts,)*
                };
                let cpi_ctx = anchor_lang::context::CpiContext::new(cpi_program, cpi_accounts);
                if (accounts.len() > #min_accounts_len) {
                    let remaining_accounts = accounts[#min_accounts_len..].to_vec();
                    return Ok(cpi_ctx.with_remaining_accounts(remaining_accounts));
                }
                Ok(cpi_ctx)
            }
        }
    };

    output.into()
}
