// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IUltraLightNode301 {
    function commitVerification(bytes calldata _packet, uint256 _gasLimit) external;
}
