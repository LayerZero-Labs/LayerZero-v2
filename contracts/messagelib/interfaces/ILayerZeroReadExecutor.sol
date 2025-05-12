// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILayerZeroReadExecutor {
    // @notice query price and assign jobs at the same time
    // @param _sender - the source sending contract address. executors may apply price discrimination to senders
    // @param _options - optional parameters for extra service plugins, e.g. sending dust tokens at the destination chain
    function assignJob(address _sender, bytes calldata _options) external returns (uint256 fee);

    // @notice query the executor price for executing the payload on this chain
    // @param _sender - the source sending contract address. executors may apply price discrimination to senders
    // @param _options - optional parameters for extra service plugins, e.g. sending dust tokens
    function getFee(address _sender, bytes calldata _options) external view returns (uint256 fee);
}
