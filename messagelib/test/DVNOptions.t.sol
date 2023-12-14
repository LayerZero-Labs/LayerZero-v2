// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { DVNOptions } from "../contracts/uln/libs/DVNOptions.sol";

import { OptionsUtil } from "./util/OptionsUtil.sol";

contract DVNOptionsTest is Test {
    using OptionsUtil for bytes;

    function test_getNumDVNs_failsOnDVNIdxGt254() public {
        bytes memory options = "";
        options = options.addDVNOption(255, 0, ""); // index 255

        vm.expectRevert(DVNOptions.InvalidDVNIdx.selector);
        DVNOptions.getNumDVNs(options);
    }

    function test_getNumDVNs_withOneDVNs() public {
        bytes memory options = "";
        options = options.addDVNPreCrimeOption(1); // dvn 1
        options = options.addDVNOption(1, type(uint8).max, abi.encodePacked(uint8(1))); // dvn 1, test a future option type
        options = options.addDVNPreCrimeOption(1); // dvn 1 overlap

        uint8 numDVNs = DVNOptions.getNumDVNs(options);
        assertEq(numDVNs, 1);
    }

    function test_getNumDVNs_withThreeDVNs() public {
        bytes memory options = "";
        options = options.addDVNPreCrimeOption(0); // dvn 0
        options = options.addDVNOption(2, type(uint8).max, abi.encodePacked(uint8(1))); // dvn 2, test a future option type
        options = options.addDVNPreCrimeOption(0); // dvn 0 overlap
        options = options.addDVNPreCrimeOption(1);

        uint8 numDVNs = DVNOptions.getNumDVNs(options);
        assertEq(numDVNs, 3);
    }

    function test_groupDVNOptionsByIdx_emptyOptions() public {
        bytes memory options;
        (bytes[] memory dvnOptions, uint8[] memory newDVNIndices) = DVNOptions.groupDVNOptionsByIdx(options);
        assertEq(dvnOptions.length, 0);
        assertEq(newDVNIndices.length, 0);
    }

    function test_groupDVNOptionsByIdx_onlyOneDVNs() public {
        bytes memory options = "";
        options = options.addDVNPreCrimeOption(5); // dvn 5

        (bytes[] memory dvnOptions, uint8[] memory newDVNIndices) = DVNOptions.groupDVNOptionsByIdx(options);
        assertEq(dvnOptions.length, 1);
        assertEq(dvnOptions[0], options);
        assertEq(newDVNIndices.length, 1);
        assertEq(newDVNIndices[0], 5);
    }

    function test_groupDVNOptionsByIdx() public {
        bytes memory options = "";
        options = options.addDVNPreCrimeOption(0); // dvn 0
        options = options.addDVNOption(2, type(uint8).max, abi.encodePacked(uint8(1))); // dvn 1, test a future option type
        options = options.addDVNPreCrimeOption(0); // dvn 0 overlap

        (bytes[] memory dvnOptions, uint8[] memory newDVNIndices) = DVNOptions.groupDVNOptionsByIdx(options);
        assertEq(newDVNIndices.length, 2);
        assertEq(newDVNIndices[0], 0);
        assertEq(newDVNIndices[1], 2);

        assertEq(dvnOptions.length, 2);
        assertEq(dvnOptions[0], hex"02000200010200020001"); // [02(dvn type), 0002(size), 00(dvn idx), 01(precrime type)] * 2
        assertEq(dvnOptions[1], hex"02000302ff01"); // 02(dvn type), 0003(size), 02(dvn idx), ff(future type), 01(future param)
    }

    function test_decodeDVNOptions() public {
        bytes memory options = "";
        options = options.addDVNPreCrimeOption(0); // dvn 0
        options = options.addDVNOption(0, type(uint8).max, abi.encodePacked(uint8(1))); // dvn 1, test a future option type
        options = options.addDVNPreCrimeOption(0); // dvn 0 overlap

        uint256 cursor;
        uint8 optionType;
        bytes memory option;

        // the first dvn option
        (optionType, option, cursor) = this.nextDVNOption(options, cursor);
        assertEq(optionType, 1);
        assertEq(option, bytes(""));
        assertEq(cursor, 5);

        // the second dvn option
        (optionType, option, cursor) = this.nextDVNOption(options, cursor);
        assertEq(optionType, type(uint8).max);
        assertEq(option, abi.encodePacked(uint8(1)));
        assertEq(cursor, 11);

        // the third dvn option
        (optionType, option, cursor) = this.nextDVNOption(options, cursor);
        assertEq(optionType, 1);
        assertEq(option, bytes(""));
        assertEq(cursor, 16);
        assertEq(cursor, options.length);
    }

    // a wrapper function for getting the calldata bytes by calling a external function
    function nextDVNOption(
        bytes calldata _options,
        uint256 _cursor
    ) external pure returns (uint8 optionType, bytes calldata option, uint256 cursor) {
        return DVNOptions.nextDVNOption(_options, _cursor);
    }
}
