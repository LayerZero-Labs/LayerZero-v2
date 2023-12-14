// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";

contract NonceContractMock {
    error OnlySendLibrary();

    ILayerZeroEndpoint public immutable endpoint;
    mapping(uint16 dstEid => mapping(bytes path => uint64 nonce)) public outboundNonce;

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
    }

    function increment(uint16 _chainId, address _ua, bytes calldata _path) external returns (uint64) {
        if (msg.sender != endpoint.getSendLibraryAddress(_ua)) {
            revert OnlySendLibrary();
        }
        return ++outboundNonce[_chainId][_path];
    }
}
