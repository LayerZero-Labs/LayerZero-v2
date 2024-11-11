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

    struct FeeParamsForRead {
        address priceFeed;
        address sender;
        uint64 quorum;
        uint16 defaultMultiplierBps;
    }

    error DVN_UnsupportedOptionType(uint8 optionType);
    error DVN_EidNotSupported(uint32 eid);
    error DVN_TimestampOutOfRange(uint32 eid, uint64 timestamp);
    error DVN_INVALID_INPUT_LENGTH();

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

    function getFeeOnSend(
        FeeParamsForRead calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _cmd,
        bytes calldata _options
    ) external payable returns (uint256 fee);

    function getFee(
        FeeParamsForRead calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _cmd,
        bytes calldata _options
    ) external view returns (uint256 fee);

    function version() external view returns (uint64 major, uint8 minor);
}
