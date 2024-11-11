// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { IExecutorFeeLib } from "../contracts/interfaces/IExecutorFeeLib.sol";
import { IExecutor } from "../contracts/interfaces/IExecutor.sol";
import { ExecutorFeeLib } from "../contracts/ExecutorFeeLib.sol";

import { PriceFeedMock } from "./mocks/PriceFeedMock.sol";

contract ExecutorFeeLibTest is Test {
    ExecutorFeeLib executorFeeLib;
    PriceFeedMock priceFeed;
    IExecutor.DstConfig config;
    uint16 defaultMultiplierBps = 12000;
    uint32 srcEid = 10000;
    uint32 dstEid = 30000;
    uint256 gasFee = 100;
    uint128 priceRatio = 1e10;
    uint128 nativePriceUSD = 2000e10;
    uint64 baseGas = 1;
    uint16 multiplierBps = 10000;
    uint128 floorMarginUSD = 3e10;
    uint128 nativeDropCap = 222000;
    uint256 calldataSize = 0;
    address oapp = address(0);
    uint128 dstGas = 200000;
    uint128 dstAmount = 5;
    uint16 index = 0;
    bytes32 nativeDropReceiver = bytes32("randomAddress");

    uint8 internal constant OPTION_TYPE_LZRECEIVE = 1;
    uint8 internal constant OPTION_TYPE_NATIVE_DROP = 2;
    uint8 internal constant OPTION_TYPE_LZCOMPOSE = 3;
    uint8 internal constant OPTION_TYPE_ORDERED_EXECUTION = 4;
    uint8 internal constant OPTION_TYPE_LZ_READ = 5;
    uint8 internal constant OPTION_TYPE_INVALID = 99;

    uint8 internal constant WORKER_ID = 1;

    function setUp() public {
        priceFeed = new PriceFeedMock();
        executorFeeLib = new ExecutorFeeLib(srcEid, 1e18);
        priceFeed.setup(gasFee, priceRatio, nativePriceUSD);
        config = IExecutor.DstConfig(baseGas, multiplierBps, floorMarginUSD, nativeDropCap, 0);
    }

    function test_getFee_noOptions_revert() public {
        vm.expectRevert(IExecutorFeeLib.Executor_NoOptions.selector);
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        executorFeeLib.getFee(params, config, "");
    }

    function test_getFee_invalidOption_revert() public {
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_INVALID)
        );
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_INVALID, dstGas, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_lzReceiveOption_defaultMultiplier() public {
        config = IExecutor.DstConfig(baseGas, 0, 0, nativeDropCap, 0);
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();

        uint256 expected = ((gasFee + dstFee) * defaultMultiplierBps) / 10000;
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );

        assertEq(actual, expected);
    }

    function test_getFee_lzReceiveOption_specificMultiplier() public {
        config = IExecutor.DstConfig(baseGas, multiplierBps, 0, nativeDropCap, 0);
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();

        uint256 expected = ((gasFee + dstFee) * multiplierBps) / 10000;
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            multiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );

        assertEq(actual, expected);
    }

    function test_getFee_lzReadOption_defaultMultiplier() public {
        config = IExecutor.DstConfig(baseGas, 0, 0, nativeDropCap, 0);
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();
        uint32 dataSize = 100;

        uint256 expected = ((gasFee + dstFee) * defaultMultiplierBps) / 10000;
        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZ_READ, dstGas, dataSize, dstAmount);
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );

        assertEq(actual, expected);
    }

    function test_getFee_lzReadOption_specificMultiplier() public {
        config = IExecutor.DstConfig(baseGas, multiplierBps, 0, nativeDropCap, 0);
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();
        uint32 dataSize = 100;

        uint256 expected = ((gasFee + dstFee) * multiplierBps) / 10000;
        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            multiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZ_READ, dstGas, dataSize, dstAmount);
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );

        assertEq(actual, expected);
    }

    function test_getFee_lzReadOption_dataSize_0_revert() public {
        config = IExecutor.DstConfig(baseGas, 0, 0, nativeDropCap, 0);
        uint32 dataSize = 0;

        vm.expectRevert(abi.encodeWithSelector(IExecutorFeeLib.Executor_ZeroCalldataSizeProvided.selector));

        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZ_READ, dstGas, dataSize, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_lzReadOption_lzReceiveGas_0_revert() public {
        config = IExecutor.DstConfig(baseGas, 0, 0, nativeDropCap, 0);
        uint32 dataSize = 100;

        vm.expectRevert(abi.encodeWithSelector(IExecutorFeeLib.Executor_ZeroLzReceiveGasProvided.selector));

        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZ_READ, uint128(0), dataSize, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_lzComposeOption_floorMargin() public {
        uint256 floorMargin = (floorMarginUSD * 1e18) / priceFeed.nativeTokenPriceUSD();
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();

        uint256 expected = gasFee + dstFee + floorMargin;
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            multiplierBps
        );

        bytes memory lzComposeOption = abi.encodePacked(OPTION_TYPE_LZCOMPOSE, index, dstGas, dstAmount);
        bytes memory lzReceiveOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, uint128(0));
        bytes memory executorOption = abi.encodePacked(
            WORKER_ID,
            uint16(lzComposeOption.length),
            lzComposeOption,
            WORKER_ID,
            uint16(lzReceiveOption.length),
            lzReceiveOption
        );

        uint256 actual = executorFeeLib.getFee(params, config, executorOption);

        assertEq(actual, expected);
    }

    function test_getFee_nativeTokenPriceZero_specificMultiplier() public {
        priceFeed.setup(gasFee + gasFee, priceRatio, 0);
        uint256 dstFee = (dstAmount * priceRatio) / priceFeed.getPriceRatioDenominator();

        uint256 expected = ((gasFee + gasFee + dstFee) * multiplierBps) / 10000;
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            multiplierBps
        );

        bytes memory lzComposeOption = abi.encodePacked(OPTION_TYPE_LZCOMPOSE, index, dstGas, dstAmount);
        bytes memory lzReceiveOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, uint128(0));
        bytes memory executorOption = abi.encodePacked(
            WORKER_ID,
            uint16(lzComposeOption.length),
            lzComposeOption,
            WORKER_ID,
            uint16(lzReceiveOption.length),
            lzReceiveOption
        );

        uint256 actual = executorFeeLib.getFee(params, config, executorOption);

        assertEq(actual, expected);
    }

    function test_getFee_nativeAmountExceedsCap_revert() public {
        uint128 nativeDropAmount = nativeDropCap + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutorFeeLib.Executor_NativeAmountExceedsCap.selector,
                nativeDropAmount,
                nativeDropCap
            )
        );
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, nativeDropAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_lzReceiveAndNativeDropOptions_floorMargin() public {
        uint128 nativeDropAmount = 1000;
        uint128 priceRatioDenominator = priceFeed.getPriceRatioDenominator();
        uint256 floorMargin = (floorMarginUSD * 1e18) / priceFeed.nativeTokenPriceUSD();
        uint256 nativeDropFee = (nativeDropAmount * priceRatio) / priceRatioDenominator;

        uint256 expected = gasFee + (dstAmount * priceRatio) / priceRatioDenominator + floorMargin + nativeDropFee;
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            oapp,
            calldataSize,
            multiplierBps
        );

        bytes memory executorOption1 = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        bytes memory executorOption2 = abi.encodePacked(OPTION_TYPE_NATIVE_DROP, nativeDropAmount, nativeDropReceiver);
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(
                WORKER_ID,
                uint16(executorOption1.length),
                executorOption1,
                WORKER_ID,
                uint16(executorOption2.length),
                executorOption2
            )
        );

        assertEq(actual, expected);
    }

    function test_getFee_Read_UnsupportedOptionType_With_LzReceiveOption_revert() public {
        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZRECEIVE) // for read getFee, not allow lzReceive options
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_Read_UnsupportedOptionType_With_NativeDropOptions_revert() public {
        IExecutorFeeLib.FeeParamsForRead memory params = IExecutorFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_NATIVE_DROP) // for read getFee, not allow native drop options
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_NATIVE_DROP, dstAmount, address(this));
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_UnsupportedOptionType_ReadOptions_revert() public {
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZ_READ) // for cross-chain getFee, not allow read options
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZ_READ, dstGas, calldataSize, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_UnsupportedOptionType_EndpointV1_LzReceiveWithValue_revert() public {
        // LzReceive with value
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZRECEIVE)
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFeeOnSend_UnsupportedOptionType_EndpointV1_LzReceiveWithValue_revert() public {
        // LzReceive with value
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZRECEIVE)
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, dstAmount);
        executorFeeLib.getFeeOnSend(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFee_EndpointV1_LzReceive() public {
        // LzReceive
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        config = IExecutor.DstConfig(baseGas, defaultMultiplierBps, 0, 0, 0);

        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, uint128(0));
        uint256 actual = executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );

        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        assertEq(actual, expected);
    }

    function test_getFeeOnSend_EndpointV1_LzReceive() public {
        // LzReceive
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        config = IExecutor.DstConfig(baseGas, defaultMultiplierBps, 0, 0, 0);

        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZRECEIVE, dstGas, uint128(0));
        uint256 actual = executorFeeLib.getFeeOnSend(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        assertEq(actual, expected);
    }

    function test_getFee_UnsupportedOptionType_EndpointV1_LzCompose_revert() public {
        // LzCompose
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZCOMPOSE)
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZCOMPOSE, index, dstGas, dstAmount);
        executorFeeLib.getFee(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }

    function test_getFeeOnSend_UnsupportedOptionType_EndpointV1_LzCompose_revert() public {
        // LzCompose
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            address(priceFeed),
            101,
            oapp,
            calldataSize,
            defaultMultiplierBps
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutorFeeLib.Executor_UnsupportedOptionType.selector, OPTION_TYPE_LZCOMPOSE)
        );
        bytes memory executorOption = abi.encodePacked(OPTION_TYPE_LZCOMPOSE, index, dstGas, dstAmount);
        executorFeeLib.getFeeOnSend(
            params,
            config,
            abi.encodePacked(WORKER_ID, uint16(executorOption.length), executorOption)
        );
    }
}
