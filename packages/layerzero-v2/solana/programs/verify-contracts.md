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

Once Homebrew is installed, the next step is to launch a virtual machine using `tart`, a tool to manage macOS virtual machines. We will clone a base macOS Sonoma image and run the virtual machine.

Clone the image and launch the virtual machine:

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

### Step 2.9: Install Repository Dependencies

Before building the program, navigate to the cloned LayerZero-v2 repository and install the necessary dependencies using `yarn`:

```bash
cd ~/Desktop/layerzero/monorepo
yarn
```

---

## Step 3: Build and Verify the Solana Contracts

### Step 3.1: Build the Solana Program

Navigate to the Solana contracts directory within the repository and build the contracts using `anchor`:

```bash
cd ~/Desktop/layerzero/monorepo/packages/layerzero-v2/solana/programs
anchor build
```

Once the build is complete, generate the SHA256 checksum for the compiled Solana program:

```bash
sha256sum ./target/deploy/endpoint.so
```

### Step 3.2: Download and Verify Program Data

To verify the bytecode deployed on the Solana network, download the program data using the Solana CLI, and compare its checksum with the one you generated.

Download the program data and save it to `/tmp/endpoint.so`:

```bash
solana program dump 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 /tmp/endpoint.so
```

Generate the checksum for the downloaded program:

```bash
sha256sum /tmp/endpoint.so
```

### Step 3.3: Compare the Results <a id="program-hash"></a>

Now, compare the checksums of the built program and the downloaded program. They should match if the deployed bytecode is identical to your local build.

| Program            | Address                                      | Commit      | SHA256                                                           |
| ------------------ | -------------------------------------------- | ------------ | ---------------------------------------------------------------- |
| blocked-messagelib | 2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB | 37c598b | f92e599beb2fdfa53e7061ce4421f91b561c2d927a722ec3399f13a42edbe125 |
| dvn                | HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW | 37c598b | b241d72e5b7fca532db12f22e128824c9316a887edbecc97f1f76fb0113e9127 |
| endpoint           | 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 | 37c598b | caa868d80b000c488e60e99828e366e773dde877ccc92b67f81df03b608639d4 |
| oft                | HRPXLCqspQocTjfcX4rvAPaY9q6Gwb1rrD3xXWrfJWdW | 37c598b | cd470fa5a7d287b4145068a546da32d5e21c71b3406d094280583e32644255b7 |
| pricefeed          | 8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP | 37c598b | e7349c171c43c971044ea0ddc4c6f75b7b1395afde2b3d9243c5e2dce7ba9459 |
| uln                | 7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH | 7aebbd7 | 3f5e4b54a281804aade7d24efd7957b30663e2f9a1f5e88ca4a6d539848f6e06 |     |


If the checksums match, the verification is successful.
