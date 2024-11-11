// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { OptionsType3Mock } from "./mock/OptionsType3Mock.sol";
import { OptionsBuilder } from "../../contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3 } from "../../contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract OAppOptionsType3Test is Test {
    using OptionsBuilder for bytes;

    function test_constructor(uint128 lzReceiveGas, uint128 lzReceiveValue) public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzReceiveGas, lzReceiveValue);
        OptionsType3Mock mock = new OptionsType3Mock(options, true);
        bytes memory actualOptions = mock.enforcedOptions(1, 1);
        assertEq(actualOptions, options, "OptionsType3Mock constructor should set enforced options");
    }

    function test_assertOptionsType3(uint128 lzReceiveGas, uint128 lzReceiveValue) public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzReceiveGas, lzReceiveValue);
        OptionsType3Mock mock = new OptionsType3Mock(options, false);
        mock.assertOptionsType3(options);
    }

    function test_assertOptionsType3_fails(uint16 prefix, bytes memory remaining) public {
        vm.assume(prefix != 3);
        bytes memory options = abi.encodePacked(bytes2(prefix), remaining);
        OptionsType3Mock mock = new OptionsType3Mock(options, false);
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, options));
        mock.assertOptionsType3(options);
    }
}
