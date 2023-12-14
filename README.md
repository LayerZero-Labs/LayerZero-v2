# LayerZero V2 - Omnichain Interoperability Protocol

LayerZero is an innovative open-source, immutable messaging protocol, that connects blockchains (50+ and counting) to enable omnichain interoperability for blockchain applications. With LayerZero V2, developers have the power to create applications that can seamlessly interact across multiple blockchains.

Refer to the [LayerZero V2 Docs](https://docs.layerzero.network/contracts/overview) for implementing, handling, and debugging LayerZero contracts.

Join the `#dev-general` channel on [Discord](https://discord-layerzero.netlify.app/discord) to discuss technical issues.

## Build & Test

```bash
yarn && yarn build && yarn test
```

## Build an Omnichain Application (OApp)

All of the contracts in `/oapp` can be referred to when building an Omnichain Application (OApp):

- **OApp**: The OApp Standard provides developers with a generic message passing interface to send and receive arbitrary pieces of data between contracts existing on different blockchain networks. See the[ OApp Quickstart](https://docs.layerzero.network/contracts/oapp) to start building.

- **OFT**: The Omnichain Fungible Token (OFT) Standard allows fungible tokens to be transferred across multiple blockchains without asset wrapping or middlechains. See the [OFT Quickstart](https://docs.layerzero.network/contracts/oft) to learn more.

## Protocol Contracts

The core, immutable protocol contracts (i.e., the [LayerZero Endpoint](https://docs.layerzero.network/explore/layerzero-endpoint)) live in `/protocol`.

## MessageLib

The contracts related to the append-only, on-chain [MessageLibs](https://docs.layerzero.network/explore/messagelib) live in `/messagelib`. Inside you can see reference implementations for how the [DVN](https://docs.layerzero.network/explore/decentralized-verifier-networks) and [Executor](https://docs.layerzero.network/explore/executors) communicate with the Ultra Light Nodes on each chain.

- **DVN**: Developers can run a custom DVN by deploying a DVN contract on every chain they want to support. See the [Build DVN](https://docs.layerzero.network/contracts/develop-dvn) guide to create your own security setup.

- **Executor**: Developers can deploy a custom Executor to ensure the seamless execution of messages on the destination chain. See the [Executor](https://docs.layerzero.network/contracts/develop-executor) guide.
