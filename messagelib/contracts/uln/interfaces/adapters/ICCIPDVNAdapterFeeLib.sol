// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { ICCIPDVNAdapter } from "./ICCIPDVNAdapter.sol";

interface ICCIPDVNAdapterFeeLib {
    struct Param {
        uint32 dstEid;
        uint64 confirmations;
        address sender;
        uint16 defaultMultiplierBps;
    }

    struct DstConfig {
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
    }

    struct DstConfigParam {
        uint32 dstEid;
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
    }

    event DstConfigSet(DstConfigParam[] params);

    error CCIPDVNAdapter_OptionsUnsupported();
    error CCIPDVNAdapter_EidNotSupported(uint32 eid);

    function getFeeOnSend(
        Param calldata _params,
        ICCIPDVNAdapter.DstConfig calldata _dstConfig,
        Client.EVM2AnyMessage calldata _message,
        bytes calldata _options,
        IRouterClient _router
    ) external payable returns (uint256 ccipFee, uint256 totalFee);

    function getFee(
        Param calldata _params,
        ICCIPDVNAdapter.DstConfig calldata _dstConfig,
        Client.EVM2AnyMessage calldata _message,
        bytes calldata _options,
        IRouterClient _router
    ) external view returns (uint256 totalFee);
}
