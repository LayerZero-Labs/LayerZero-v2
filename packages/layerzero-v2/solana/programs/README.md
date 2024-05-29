## Prerequisites

- [rust](https://www.rust-lang.org/tools/install) (nightly)
- [solana](https://docs.solana.com/cli/install-solana-cli-tools) (v1.14.17)
- [anchor](https://book.anchor-lang.com/getting_started/installation.html) (v0.27.0)
- [jq](https://stedolan.github.io/jq/download/)

## Install

`anchor build` will install the dependencies automatically. If you want to install the dependencies manually, run the following command:

```shell
rustup default nightly
```

## Build

```shell
anchor build
```

## Test

```shell
yarn test
```

or

```shell
TEST_SCOPES=uln yarn test
```

or

```shell
anchor test --skip-build
```

## deploy

The public keypair(solana/keypair) files are backed up from the target/deploy folder, which is used to deploy the program on the Solana network.

```shell
solana program deploy --program-id ./keypair/xxx.json ./target/deploy/xxx.so
```
