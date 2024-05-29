extern crate proc_macro;

mod codecs;
mod default_env;

use proc_macro::TokenStream;
use quote::quote;
use syn::parse_macro_input;
use syn::LitStr;

#[proc_macro]
pub fn program_id_from_env(input: TokenStream) -> TokenStream {
    let self::default_env::DefaultEnv {
        env_var,
        default_value,
    } = parse_macro_input!(input as self::default_env::DefaultEnv);

    let var_or_default = match std::env::var(env_var.value()) {
        Ok(var) => quote! { #var },
        Err(_) => quote! { #default_value },
    };
    let resolved = TokenStream::from(var_or_default);
    let value: LitStr = syn::parse(resolved).unwrap();
    let tokens: proc_macro2::TokenStream = self::codecs::parse_bs58(&value).unwrap();
    let output = TokenStream::from(tokens);

    output
}
