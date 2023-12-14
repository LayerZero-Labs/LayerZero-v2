// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { UlnOptions as UlnOptionsImpl } from "../contracts/uln/libs/UlnOptions.sol";

import { OptionsUtil } from "./util/OptionsUtil.sol";

library UlnOptions {
    function decode(
        bytes calldata _options
    ) external pure returns (bytes memory executorOptions, bytes memory dvnOptions) {
        return UlnOptionsImpl.decode(_options);
    }
}

contract UlnOptionsTest is Test {
    using OptionsUtil for bytes;
    using BytesLib for bytes;

    function test_decode_type1() public {
        uint128 executeGas = 20000;
        bytes memory legacyOptions = OptionsUtil.encodeLegacyOptionsType1(executeGas);
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(legacyOptions);

        bytes memory t3Options = "";
        t3Options = t3Options.addExecutorLzReceiveOption(executeGas, 0);
        assertEq(executorOptions, t3Options);
        assertEq(dvnOptions, "");
    }

    function test_decode_type2() public {
        uint128 executeGas = 20000;
        uint128 amount = 10000;
        address receiver = address(0x1234);
        bytes memory legacyOptions = OptionsUtil.encodeLegacyOptionsType2(
            executeGas,
            amount,
            abi.encodePacked(receiver)
        );
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(legacyOptions);

        bytes memory t3Options = "";
        t3Options = t3Options.addExecutorLzReceiveOption(executeGas, 0).addExecutorNativeDropOption(
            amount,
            AddressCast.toBytes32(receiver)
        );
        assertEq(executorOptions, t3Options);
        assertEq(dvnOptions, "");
    }

    function test_decode_type3_executor_with_1_option() public {
        uint128 executeGas = 20000;
        bytes memory t3Options = OptionsUtil.newOptions().addExecutorLzReceiveOption(executeGas, 0);
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(t3Options);

        assertEq(executorOptions, OptionsUtil.trimType(t3Options));
        assertEq(dvnOptions, "");
    }

    function test_decode_type3_executor_with_n_option() public {
        uint128 executeGas = 20000;
        uint128 amount = 10000;
        address receiver = address(0x1234);
        bytes memory t3Options = OptionsUtil
            .newOptions()
            .addExecutorLzReceiveOption(executeGas, 0)
            .addExecutorNativeDropOption(amount, AddressCast.toBytes32(receiver));
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(t3Options);

        assertEq(executorOptions, OptionsUtil.trimType(t3Options));
        assertEq(dvnOptions, "");
    }

    function test_decode_type3_dvn_with_1_option() public {
        bytes memory t3Options = OptionsUtil.newOptions().addDVNPreCrimeOption(1);
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(t3Options);

        assertEq(executorOptions, "");
        assertEq(dvnOptions, OptionsUtil.trimType(t3Options));
    }

    function test_decode_type3_dvn_with_n_option() public {
        bytes memory t3Options = OptionsUtil
            .newOptions()
            .addDVNPreCrimeOption(1)
            .addDVNPreCrimeOption(2)
            .addDVNPreCrimeOption(3)
            .addDVNPreCrimeOption(4);
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(t3Options);

        assertEq(executorOptions, "");
        assertEq(dvnOptions, OptionsUtil.trimType(t3Options));
    }

    function test_decode_type3_dvn_with_n_option_and_executor_with_n_option() public {
        uint128 executeGas = 20000;
        uint128 amount = 10000;
        address receiver = address(0x1234);
        bytes memory t3Options = OptionsUtil
            .newOptions()
            .addDVNPreCrimeOption(1)
            .addExecutorLzReceiveOption(executeGas, 0)
            .addDVNPreCrimeOption(2)
            .addExecutorNativeDropOption(amount, AddressCast.toBytes32(receiver))
            .addDVNPreCrimeOption(3)
            .addDVNPreCrimeOption(4);
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(t3Options);

        bytes memory t3ExecutorOptions = "";
        t3ExecutorOptions = t3ExecutorOptions.addExecutorLzReceiveOption(executeGas, 0).addExecutorNativeDropOption(
            amount,
            AddressCast.toBytes32(receiver)
        );
        bytes memory t3DVNOptions = "";
        t3DVNOptions = t3DVNOptions
            .addDVNPreCrimeOption(1)
            .addDVNPreCrimeOption(2)
            .addDVNPreCrimeOption(3)
            .addDVNPreCrimeOption(4);

        assertEq(executorOptions, t3ExecutorOptions);
        assertEq(dvnOptions, t3DVNOptions);
    }

    function test_decode_type3_options_invalid_size() public {
        // case 1: add one more byte to make it invalid
        bytes memory t3Options = OptionsUtil.newOptions().addExecutorLzReceiveOption(20000, 0);
        t3Options = t3Options.concat(hex"aa");

        vm.expectRevert();
        UlnOptions.decode(t3Options);

        // case 2: remove the last byte to make it invalid
        t3Options = OptionsUtil.newOptions().addExecutorLzReceiveOption(20000, 0);
        t3Options = t3Options.slice(0, t3Options.length - 1);

        vm.expectRevert();
        UlnOptions.decode(t3Options);
    }

    function test_decode_type3_options_invalid_worker_id() public {
        uint8 workerId = 0;
        uint8 optionType = 1;
        bytes memory t3Options = OptionsUtil.newOptions().addOption(workerId, optionType, bytes("abcd"));

        vm.expectRevert(abi.encodeWithSelector(UlnOptionsImpl.InvalidWorkerId.selector, 0));
        UlnOptions.decode(t3Options);
    }
}
