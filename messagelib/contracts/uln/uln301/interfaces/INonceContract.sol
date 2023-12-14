// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface INonceContract {
    function increment(uint16 _chainId, address _ua, bytes calldata _path) external returns (uint64);
}
