// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IOAppComputerReduce {
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external view returns (bytes memory);
}
