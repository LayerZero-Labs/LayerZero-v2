# Verify LayerZero-v2 Solana Bytecode

This guide will walk you through verifying the bytecode for LayerZero-v2 on Solana. The procedure involves setting up a macOS virtual machine, installing the necessary tools, and performing the verification. This document assumes you are familiar with command-line operations and version control.

## Prerequisites

Before starting, ensure you are working on a Mac that supports the installation of `Brew` and has sufficient resources to run a virtual machine.

### Step 1: Set Up Homebrew and Launch the Virtual Machine

First, you will need to install Homebrew, a package manager for macOS, to manage dependencies easily.

Install Homebrew by running the following command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Once Homebrew is installed, the next step is to install `tart`, a tool to manage macOS virtual machines.

```bash
brew install cirruslabs/cli/tart
```

Clone the base macOS Sonoma image and launch the virtual machine:

```bash
tart clone ghcr.io/cirruslabs/macos-sonoma-base:latest sonoma-base
tart run sonoma-base
```

**Note:** After completing the verification, remember to remove the virtual machine to free up system resources:

```bash
tart delete sonoma-base
```

For accessing the virtual machine, use the following default credentials:

- **Username:** `admin`
- **Password:** `admin`

To SSH into the virtual machine, run the following:

```bash
ssh admin@$(tart ip sonoma-base)
```

You will now be connected to the virtual machine.

---

## Step 2: Configuration Inside the Virtual Machine

Once inside the virtual machine, you need to configure it by creating an account with administrative privileges and installing several essential tools.

### Step 2.1: Create a User Account with Admin Rights

Create a new user account with the name `carmencheng` and grant administrative privileges to it:

```bash
sudo sysadminctl -addUser carmencheng -fullName "" -password admin
sudo dscl . -append /Groups/admin GroupMembership carmencheng
```

Note:  You *must* use `carmencheng` as the username due to tooling limitations.

After creating the account, switch to it by running:

```bash
su - carmencheng
```

### Step 2.2: Install Homebrew and Core Utilities

Next, install Homebrew (if it’s not installed yet) and the `coreutils` package, which contains tools like `sha256sum` that will be needed later.

To install Homebrew, use the following command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Once Homebrew is installed, ensure the environment is set up correctly by adding it to your `.zprofile`:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/carmencheng/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Now install `coreutils`:

```bash
brew install coreutils
```

### Step 2.3: Clone the LayerZero Repository

Next, clone the LayerZero-v2 repository to a directory on the virtual machine:

```bash
git clone https://github.com/LayerZero-Labs/LayerZero-v2.git ~/Desktop/layerzero/monorepo
```

Check out the specific commit required for this verification:

```bash
cd ~/Desktop/layerzero/monorepo
git checkout 37c598b3e6e218c5e00c8b0dcd42f984e5b13147
```

Refer to the [Program Hash Table](#program-hash) to find the commit associated with different programs.

### Step 2.4: Install Node Version Manager (NVM) and Node.js

To manage Node.js versions, install `nvm` (Node Version Manager). This is required for running JavaScript tools involved in building the monorepo.

Install `nvm`:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

Now, install Node.js version 20:

```bash
nvm install 20
```

### Step 2.5: Enable Corepack

Enable `corepack`, which will help in managing package managers like `yarn`:

```bash
corepack enable
```

### Step 2.6: Install Rust

Rust is required for building and deploying Solana programs. Install Rust using the following command, specifying version 1.75.0:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain=1.75.0

. "$HOME/.cargo/env"
```

### Step 2.7: Install Solana Tools

Now, install Solana CLI tools, which will allow you to interact with the Solana network and build Solana programs.

Run the following command to install the Solana toolset:

```bash
curl -o- -sSfL https://release.solana.com/v1.17.31/install | bash

export PATH="/Users/carmencheng/.local/share/solana/install/active_release/bin:$PATH"
```

### Step 2.8: Install Anchor

Anchor is a framework for developing Solana smart contracts. Install `anchor` using the command below:

```bash
cargo install --git https://github.com/coral-xyz/anchor avm --force
avm install 0.29.0
avm use 0.29.0
```

### Step 2.9: Install solana-verify

`solana-verify` is a tool used to verify that the hash of the on-chain program matches the hash of the locally compiled program. By default, `solana-verify` removes any trailing zeros from the program executable and computes its hash using the `sha256` algorithm. You can install `solana-verify` using the following command:

```bash
cargo install solana-verify
```

**Note:** Starting from Solana version 1.18, new program deployments will use the exact program size.

> By default, new program deployments use the exact size of the program rather than doubling the size. If a program needs more space for an upgrade, the program account must be extended using `solana program extend` before upgrading.

If a program was deployed using Solana versions earlier than 1.18, the size of the file generated by `solana program dump` may differ from the locally built program size.

### Step 2.10: Install Repository Dependencies

Before building the program, navigate to the cloned LayerZero-v2 repository and install the necessary dependencies using `yarn`:

```bash
cd ~/Desktop/layerzero/monorepo
yarn
```

Note: Ensure you confirm when prompted to install yarn:

```text
! Corepack is about to download https://repo.yarnpkg.com/4.0.2/packages/yarnpkg-cli/bin/yarn.js
? Do you want to continue? [Y/n] y
```

---

## Step 3: Build and Verify the Solana Contracts

### Step 3.1: Build the Solana Program

Navigate to the Solana contracts directory within the repository and build the contracts using `anchor`:

```bash
cd ~/Desktop/layerzero/monorepo/packages/layerzero-v2/solana/programs
anchor build
```

Once the build is complete, generate the program hash for the compiled Solana program:

```bash
solana-verify get-executable-hash ./target/deploy/endpoint.so
```

### Step 3.2: Download and Verify Program Data

To verify the bytecode deployed on the Solana network, generate the program hash for the program.

```bash
solana-verify get-program-hash -u  https://api.mainnet-beta.solana.com 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6
```

### Step 3.3: Compare the Results

Now, compare the program hash of the built program and the on-chain program. They should match if the deployed bytecode is identical to your local build.

| Program            | Address                                      | Commit  | Platform             | Program Hash                                                     |
| ------------------ | -------------------------------------------- | ------- | -------------------- | ---------------------------------------------------------------- |
| blocked-messagelib | 2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB | 37c598b | aarch64-apple-darwin | e8f5412527e5138f626299c9b78a2e2f859d306f4c744472d7a2fde34988f3b1 |
| dvn                | HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW | 37c598b | aarch64-apple-darwin | 98c89ebdd94b2563d3aabba118ce012965c344e98c70600f66365dae2d66de39 |
| endpoint           | 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 | 37c598b | aarch64-apple-darwin | 9012552d8a15d230791e2582e6320eff872a651fb110d2198020ed12e5547e74 |
| executor           | 6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn | 2b168f1 | aarch64-apple-darwin | b17a413d00a54e8c666cf57797884504702ac032e8022fb0fa9c84516ef534f1 |
| oft                | HRPXLCqspQocTjfcX4rvAPaY9q6Gwb1rrD3xXWrfJWdW | 37c598b | aarch64-apple-darwin | b4feeed20ca0ff9be4398b5478c10ba7fd06746605d5f57552d36bc73f5ecc20 |
| pricefeed          | 8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP | 37c598b | aarch64-apple-darwin | 5209029bd51341cc70af6d1d82d182dae6dd90076265c7300434d0c5b6e8f2d6 |
| uln                | 7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH | 7aebbd7 | aarch64-apple-darwin | 325085140b5d375d2250732a231120076f45ca8a582caf56b54fc9c33319d9af |

If the checksums match, the verification is successful.
