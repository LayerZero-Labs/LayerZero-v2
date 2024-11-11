// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ICCIPDVNAdapter {
    struct DstConfigParam {
        uint32 eid;
        uint16 multiplierBps;
        uint64 chainSelector;
        uint256 gas;
        bytes peer;
    }

    struct DstConfig {
        // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#ethereum-sepolia
        // https://docs.chain.link/ccip/supported-networks/v1_0_0/mainnet
        uint64 chainSelector;
        uint16 multiplierBps;
        // https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/libraries/Client.sol#L22C51-L22C51
        // for destination is evm chain, need to use `abi.encode(address)` to get the peer
        bytes peer;
        uint256 gas;
    }

    struct SrcConfig {
        uint32 eid;
        bytes peer;
    }

    event DstConfigSet(DstConfigParam[] params);

    error CCIPDVNAdapter_UntrustedPeer(uint64 chainSelector, bytes peer);
    error CCIPDVNAdapter_InvalidRouter(address router);
}
