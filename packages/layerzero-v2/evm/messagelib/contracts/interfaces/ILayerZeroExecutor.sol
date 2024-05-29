// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILayerZeroExecutor {
    // @notice query price and assign jobs at the same time
    // @param _dstEid - the destination endpoint identifier
    // @param _sender - the source sending contract address. executors may apply price discrimination to senders
    // @param _calldataSize - dynamic data size of message + caller params
    // @param _options - optional parameters for extra service plugins, e.g. sending dust tokens at the destination chain
    function assignJob(
        uint32 _dstEid,
        address _sender,
        uint256 _calldataSize,
        bytes calldata _options
    ) external returns (uint256 price);

    // @notice query the executor price for relaying the payload and its proof to the destination chain
    // @param _dstEid - the destination endpoint identifier
    // @param _sender - the source sending contract address. executors may apply price discrimination to senders
    // @param _calldataSize - dynamic data size of message + caller params
    // @param _options - optional parameters for extra service plugins, e.g. sending dust tokens at the destination chain
    function getFee(
        uint32 _dstEid,
        address _sender,
        uint256 _calldataSize,
        bytes calldata _options
    ) external view returns (uint256 price);
}
