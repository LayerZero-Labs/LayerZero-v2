// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { IDVN } from "../contracts/uln/interfaces/IDVN.sol";
import { IDVNFeeLib } from "../contracts/uln/interfaces/IDVNFeeLib.sol";
import { DVNFeeLib } from "../contracts/uln/dvn/DVNFeeLib.sol";

import { PriceFeedMock } from "./mocks/PriceFeedMock.sol";

contract DVNFeeLibTest is Test {
    uint16 constant EXECUTE_FIXED_BYTES = 68;
    uint16 constant SIGNATURE_RAW_BYTES = 65;
    uint16 constant UPDATE_HASH_BYTES = 224;

    DVNFeeLib dvnFeeLib;
    PriceFeedMock priceFeed;
    IDVN.DstConfig config;
    uint16 defaultMultiplierBps = 12000;
    uint32 dstEid = 101;
    uint256 gasFee = 100;
    uint128 priceRatio = 1e10;
    uint128 nativePriceUSD = 2000e10;
    uint64 gas = 0;
    uint16 multiplierBps = 10000;
    uint128 floorMarginUSD = 3e10;
    uint64 quorum = 3;
    address oapp = address(0);
    uint64 confirmations = 15;

    function setUp() public {
        priceFeed = new PriceFeedMock();
        dvnFeeLib = new DVNFeeLib(1e18);
        priceFeed.setup(gasFee, priceRatio, nativePriceUSD);
    }

    // quorum * signatureRawBytes == 0
    function test_getFee_notPadded_defaultMultiplier() public {
        quorum = 32;
        config = IDVN.DstConfig(gas, 0, 0);

        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    // quorum * signatureRawBytes != 0
    function test_getFee_padded_defaultMultiplier() public {
        config = IDVN.DstConfig(gas, 0, 0);

        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_specificMultiplier() public {
        config = IDVN.DstConfig(gas, multiplierBps, 0);

        uint256 expected = (gasFee * multiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_floorMargin() public {
        config = IDVN.DstConfig(gas, multiplierBps, floorMarginUSD);

        uint256 expected = gasFee + (floorMarginUSD * 1e18) / nativePriceUSD;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_nativeTokenPriceZero_specificMultiplier() public {
        config = IDVN.DstConfig(gas, multiplierBps, floorMarginUSD);
        priceFeed.setup(gasFee, priceRatio, 0);

        uint256 expected = (gasFee * multiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }
}
