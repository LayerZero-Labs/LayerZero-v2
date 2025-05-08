// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IAxelarDVNAdapter {
    struct MultiplierParam {
        uint32 dstEid;
        uint16 multiplierBps;
    }

    struct FloorMarginUSDParam {
        uint32 dstEid;
        uint128 floorMarginUSD;
    }

    struct NativeGasFeeParam {
        uint32 dstEid;
        uint256 nativeGasFee;
    }

    struct DstConfigParam {
        uint32 eid;
        string chainName;
        string peer;
        uint16 multiplierBps;
        uint256 nativeGasFee;
    }

    struct DstConfig {
        string chainName;
        string peer;
        uint16 multiplierBps;
        uint256 nativeGasFee;
    }

    struct SrcConfig {
        uint32 eid;
        string peer;
    }

    event DstConfigSet(DstConfigParam[] params);
    event NativeGasFeeSet(NativeGasFeeParam[] params);
    event MultiplierSet(MultiplierParam[] params);
    event FloorMarginUSDSet(FloorMarginUSDParam[] params);

    error AxelarDVNAdapter_UntrustedPeer(string chainName, string peer);
    error AxelarDVNAdapter_OnlyWorkerFeeLib();

    function withdrawToFeeLib(address _sendLib) external;
}
