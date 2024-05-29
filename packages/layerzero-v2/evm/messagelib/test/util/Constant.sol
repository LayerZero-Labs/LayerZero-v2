// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constant {
    // uln301 lib version
    uint16 internal constant MSG_VERSION = 1;

    uint16 internal constant EID_ETHEREUM = 101;
    uint16 internal constant EID_BSC = 102;

    uint256 internal constant TREASURY_GAS_CAP = 100000;
    uint256 internal constant TREASURY_GAS_FOR_FEE_CAP = 100000;

    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;
    uint32 internal constant CONFIG_TYPE_UNKNOWN = 11111;

    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
    uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;
}
