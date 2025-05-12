// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { IWorker } from "../../interfaces/IWorker.sol";
import { ILayerZeroDVN } from "./ILayerZeroDVN.sol";
import { ILayerZeroReadDVN } from "./ILayerZeroReadDVN.sol";

interface IDVN is IWorker, ILayerZeroDVN, ILayerZeroReadDVN {
    struct DstConfigParam {
        uint32 dstEid;
        uint64 gas;
        uint16 multiplierBps;
        uint128 floorMarginUSD;
    }

    struct DstConfig {
        uint64 gas;
        uint16 multiplierBps;
        uint128 floorMarginUSD; // uses priceFeed PRICE_RATIO_DENOMINATOR
    }

    event SetDstConfig(DstConfigParam[] params);

    function dstConfig(uint32 _dstEid) external view returns (uint64, uint16, uint128);
}
