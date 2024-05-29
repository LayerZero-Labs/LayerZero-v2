extern crate proc_macro;

use bs58;
use proc_macro2::Span;
use quote::quote;
use syn::{LitByte, LitStr, Result};

pub fn parse_bs58(literal: &LitStr) -> Result<proc_macro2::TokenStream> {
    let id_vec = bs58::decode(literal.value())
        .into_vec()
        .map_err(|_| syn::Error::new_spanned(literal, "failed to decode base58 string"))?;
    let id_array = <[u8; 32]>::try_from(<&[u8]>::clone(&&id_vec[..])).map_err(|_| {
        syn::Error::new_spanned(
            literal,
            format!("pubkey array is not 32 bytes long: len={}", id_vec.len()),
        )
    })?;
    let bytes = id_array.iter().map(|b| LitByte::new(*b, Span::call_site()));
    Ok(quote! {
            [#(#bytes,)*]
    })
}
