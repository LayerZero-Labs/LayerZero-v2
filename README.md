<div align="center">
  <a href="https://layerzero.network">
    <img alt="LayerZero" style="width: 20%" src="https://layerzero.network/static/logo.svg"/>
  </a>

  <h1>LayerZero V2</h1>

  <p>
    <strong>Omnichain Interoperability Protocol</strong>
  </p>

  <p>
    <a href="https://docs.layerzero.network/v2"><img alt="Tutorials" src="https://img.shields.io/badge/docs-tutorials-blueviolet" /></a>
  </p>
</div>

LayerZero is an immutable, censorship-resistant, and permissionless messaging protocol, that connects blockchains (60+ and counting) to enable omnichain interoperability for blockchain applications. 

With LayerZero V2, developers have the power to create applications that can seamlessly interact across multiple blockchains.

- [Solidity Contract Standards](https://docs.layerzero.network/v2/developers/evm/overview) for sending arbitrary data, tokens, and external calls to multiple chains.
- Configure any number and type of [decentralized verifier networks (DVNs)](https://docs.layerzero.network/v2/home/modular-security/security-stack-dvns) to verify your application's cross-chain messages.
- [Executors](https://docs.layerzero.network/v2/home/permissionless-execution/executors) that, for a fee, abstract away destination gas and automatically deliver messages on behalf of the source sender.

Refer to the [LayerZero V2 Docs](https://docs.layerzero.network/v2) for implementing, handling, and debugging LayerZero contracts.

Join the `#dev-general` channel on [Discord](https://discord-layerzero.netlify.app/discord) to discuss technical issues.

[Audit Reports](https://github.com/LayerZero-Labs/Audits)

## Build & Test

```bash
yarn && yarn build && yarn test
```

## Build an Omnichain Application (OApp)

All of the contracts in `/oapp` can be referred to when building an Omnichain Application (OApp):

- **OApp**: The OApp Standard provides developers with a generic message passing interface to send and receive arbitrary pieces of data between contracts existing on different blockchain networks. See the[ OApp Quickstart](https://docs.layerzero.network/v2/developers/evm/oapp/overview) to start building.

- **OFT**: The Omnichain Fungible Token (OFT) Standard allows fungible tokens to be transferred across multiple blockchains without asset wrapping or middlechains. See the [OFT Quickstart](https://docs.layerzero.network/v2/developers/evm/oft/quickstart) to learn more.

## Protocol Contracts

The core, immutable protocol contract interfaces (i.e., the [LayerZero Endpoint](https://docs.layerzero.network/v2/home/protocol/layerzero-endpoint)) live in `/protocol`.

## MessageLib

The contracts related to the append-only, on-chain [MessageLibs](https://docs.layerzero.network/v2/home/protocol/message-library) live in `/messagelib`. Inside you can see reference implementations for how the [DVN](https://docs.layerzero.network/v2/home/modular-security/security-stack-dvns) and [Executor](https://docs.layerzero.network/v2/home/permissionless-execution/executors) communicate with the Ultra Light Nodes on each chain.

- **DVN**: Developers can run a custom DVN by deploying a DVN contract on every chain they want to support. See the [Build DVN](https://docs.layerzero.network/v2/developers/evm/off-chain/build-dvns) guide to create your own security setup.

- **Executor**: Developers can deploy a custom Executor to ensure the seamless execution of messages on the destination chain. See the [Executor](https://docs.layerzero.network/v2/developers/evm/off-chain/build-executors) guide.

## Verify Contracts
- [Solana](./packages/layerzero-v2/solana/programs/verify-contracts.md)
