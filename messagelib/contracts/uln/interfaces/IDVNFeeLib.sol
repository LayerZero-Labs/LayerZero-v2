// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { IDVN } from "./IDVN.sol";

interface IDVNFeeLib {
    struct FeeParams {
        address priceFeed;
        uint32 dstEid;
        uint64 confirmations;
        address sender;
        uint64 quorum;
        uint16 defaultMultiplierBps;
    }

    error DVN_UnsupportedOptionType(uint8 optionType);

    function getFeeOnSend(
        FeeParams calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external payable returns (uint256 fee);

    function getFee(
        FeeParams calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 fee);
}
