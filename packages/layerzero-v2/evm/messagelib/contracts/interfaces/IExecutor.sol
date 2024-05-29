// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { IWorker } from "./IWorker.sol";
import { ILayerZeroExecutor } from "./ILayerZeroExecutor.sol";

interface IExecutor is IWorker, ILayerZeroExecutor {
    struct DstConfigParam {
        uint32 dstEid;
        uint64 baseGas;
        uint16 multiplierBps;
        uint128 floorMarginUSD;
        uint128 nativeCap;
    }

    struct DstConfig {
        uint64 baseGas; // for verifying / fixed calldata overhead
        uint16 multiplierBps;
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
        uint128 nativeCap;
    }

    struct ExecutionParams {
        address receiver;
        Origin origin;
        bytes32 guid;
        bytes message;
        bytes extraData;
        uint256 gasLimit;
    }

    struct NativeDropParams {
        address receiver;
        uint256 amount;
    }

    event DstConfigSet(DstConfigParam[] params);
    event NativeDropApplied(Origin origin, uint32 dstEid, address oapp, NativeDropParams[] params, bool[] success);

    function dstConfig(uint32 _dstEid) external view returns (uint64, uint16, uint128, uint128);
}
