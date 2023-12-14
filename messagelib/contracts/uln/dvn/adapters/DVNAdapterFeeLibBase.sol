// SPDX-License-Identifier: LZBL-1.2

pragma solidity 0.8.22;

import { IDVNAdapterFeeLib } from "../../interfaces/IDVNAdapterFeeLib.sol";

contract DVNAdapterFeeLibBase is IDVNAdapterFeeLib {
    uint16 internal constant BPS_DENOMINATOR = 10000;

    function getFee(
        uint32 /*_dstEid*/,
        address /*_sender*/,
        uint16 _defaultMultiplierBps,
        uint16 _multiplierBps,
        uint256 _executionFee
    ) public pure virtual returns (uint256 fee) {
        uint256 multiplier = _multiplierBps == 0 ? _defaultMultiplierBps : _multiplierBps;
        fee = (_executionFee * multiplier) / BPS_DENOMINATOR;
    }
}
