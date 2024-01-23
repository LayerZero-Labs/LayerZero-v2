// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { IAxelarDVNAdapter } from "./IAxelarDVNAdapter.sol";

interface IAxelarDVNAdapterFeeLib {
    struct Param {
        uint32 dstEid;
        uint64 confirmations;
        address sender;
        uint16 defaultMultiplierBps;
    }

    struct DstConfig {
        uint64 gas;
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
    }

    struct DstConfigParam {
        uint32 dstEid;
        uint64 gas;
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
    }

    event DstConfigSet(DstConfigParam[] params);
    event TokenWithdrawn(address token, address to, uint256 amount);
    event GasServiceSet(address gasService);
    event PriceFeedSet(address priceFeed);
    event NativeGasFeeMultiplierBpsSet(uint16 multiplierBps);

    error AxelarDVNAdapter_OptionsUnsupported();
    error AxelarDVNAdapter_InsufficientBalance(uint256 actual, uint256 requested);

    function getFeeOnSend(
        Param calldata _params,
        IAxelarDVNAdapter.DstConfig calldata _dstConfig,
        bytes memory _payload,
        bytes calldata _options,
        address _sendLib
    ) external payable returns (uint256 totalFee);

    function getFee(
        Param calldata _params,
        IAxelarDVNAdapter.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 totalFee);
}
