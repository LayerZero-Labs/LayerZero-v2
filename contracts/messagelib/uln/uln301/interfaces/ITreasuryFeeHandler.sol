// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ITreasuryFeeHandler {
    function payFee(
        address _lzToken,
        address _sender,
        uint256 _required,
        uint256 _supplied,
        address _treasury
    ) external;
}
