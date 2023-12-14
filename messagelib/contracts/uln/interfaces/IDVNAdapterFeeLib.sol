// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IDVNAdapterFeeLib {
    function getFee(
        uint32 _dstEid,
        address _sender,
        uint16 _defaultMultiplierBps,
        uint16 _multiplierBps,
        uint256 _executionFee
    ) external view returns (uint256 fee);
}
