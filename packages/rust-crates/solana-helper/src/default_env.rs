use syn::{
    parse::{Parse, ParseStream},
    LitStr, Token,
};

pub struct DefaultEnv {
    pub env_var: LitStr,
    pub default_value: proc_macro2::TokenStream,
}

impl Parse for DefaultEnv {
    fn parse(input: ParseStream) -> syn::parse::Result<Self> {
        let env_var = input.parse()?;
        input.parse::<Token![,]>()?;
        let default_value = input.parse()?;
        Ok(Self {
            env_var,
            default_value,
        })
    }
}
