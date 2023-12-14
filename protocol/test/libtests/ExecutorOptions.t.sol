// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ExecutorOptions } from "../../contracts/messagelib/libs/ExecutorOptions.sol";

contract ExecutorOptionsTest is Test {
    function test_nextExecutorOption() public {
        bytes memory option = ExecutorOptions.encodeLzReceiveOption(1, 2);
        bytes memory options = abi.encodePacked(
            ExecutorOptions.WORKER_ID,
            uint16(option.length + 1), // option type + option length
            ExecutorOptions.OPTION_TYPE_LZRECEIVE,
            option
        );

        (uint8 optionType, bytes memory actualOption, uint256 cursor) = ExecutorOptionsWrapper.nextExecutorOption(
            options,
            0
        );
        assertEq(optionType, ExecutorOptions.OPTION_TYPE_LZRECEIVE);
        assertEq(actualOption, option);
        assertEq(cursor, options.length);
    }

    function test_lzReceiveOption() public {
        bytes memory option = ExecutorOptions.encodeLzReceiveOption(1, 0);
        assertEq(option.length, 16);

        (uint128 gas, uint128 value) = ExecutorOptionsWrapper.decodeLzReceiveOption(option);
        assertEq(gas, 1);
        assertEq(value, 0);

        option = ExecutorOptions.encodeLzReceiveOption(1, 2);
        assertEq(option.length, 32);

        (gas, value) = ExecutorOptionsWrapper.decodeLzReceiveOption(option);
        assertEq(gas, 1);
        assertEq(value, 2);
    }

    function test_nativeDropOption() public {
        bytes memory option = ExecutorOptions.encodeNativeDropOption(1, bytes32(uint256(0x1234)));
        assertEq(option.length, 48);

        (uint128 value, bytes32 receiver) = ExecutorOptionsWrapper.decodeNativeDropOption(option);
        assertEq(value, 1);
        assertEq(receiver, bytes32(uint256(0x1234)));
    }

    function test_lzComposeOption() public {
        bytes memory option = ExecutorOptions.encodeLzComposeOption(0, 1, 0);
        assertEq(option.length, 18);

        (uint16 index, uint128 gas, uint128 value) = ExecutorOptionsWrapper.decodeLzComposeOption(option);
        assertEq(index, 0);
        assertEq(gas, 1);
        assertEq(value, 0);

        option = ExecutorOptions.encodeLzComposeOption(0, 1, 2);
        assertEq(option.length, 34);

        (index, gas, value) = ExecutorOptionsWrapper.decodeLzComposeOption(option);
        assertEq(index, 0);
        assertEq(gas, 1);
        assertEq(value, 2);
    }
}

library ExecutorOptionsWrapper {
    function nextExecutorOption(
        bytes calldata _options,
        uint256 _cursor
    ) external pure returns (uint8 optionType, bytes memory option, uint256 cursor) {
        return ExecutorOptions.nextExecutorOption(_options, _cursor);
    }

    function decodeLzReceiveOption(bytes calldata _option) external pure returns (uint128 gas, uint128 value) {
        return ExecutorOptions.decodeLzReceiveOption(_option);
    }

    function decodeNativeDropOption(bytes calldata _option) external pure returns (uint128 amount, bytes32 receiver) {
        return ExecutorOptions.decodeNativeDropOption(_option);
    }

    function decodeLzComposeOption(
        bytes calldata _option
    ) external pure returns (uint16 index, uint128 gas, uint128 value) {
        return ExecutorOptions.decodeLzComposeOption(_option);
    }
}
