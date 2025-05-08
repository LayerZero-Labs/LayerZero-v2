// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILayerZeroReadDVN {
    // @notice query price and assign jobs at the same time
    // @param _packetHeader - version + nonce + path
    // @param _cmd - the command to be executed to obtain the payload
    // @param _options - options
    function assignJob(
        address _sender,
        bytes calldata _packetHeader,
        bytes calldata _cmd,
        bytes calldata _options
    ) external payable returns (uint256 fee);

    // @notice query the dvn fee for relaying block information to the destination chain
    // @param _packetHeader - version + nonce + path
    // @param _cmd - the command to be executed to obtain the payload
    // @param _options - options
    function getFee(
        address _sender,
        bytes calldata _packetHeader,
        bytes calldata _cmd,
        bytes calldata _options
    ) external view returns (uint256 fee);
}
