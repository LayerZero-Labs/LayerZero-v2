// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";

import { DVNAdapterFeeLibBase } from "../contracts/uln/dvn/adapters/DVNAdapterFeeLibBase.sol";

contract DVNAdapterFeeLibBaseTest is DVNAdapterFeeLibBase, Test {
    uint256 constant MIN_EXECUTION_FEE = 0;
    uint256 constant MAX_EXECUTION_FEE = 1 ether;
    uint16 constant MAX_MULTIPLIER_BPS = 20000;

    function testFuzz_getFee_useDefaultMultiplier(uint16 defaultMultiplierBps, uint256 executionFee) public {
        uint16 multiplierBps = 0;
        defaultMultiplierBps = uint16(bound(defaultMultiplierBps, 0, MAX_MULTIPLIER_BPS));
        executionFee = bound(executionFee, MIN_EXECUTION_FEE, MAX_EXECUTION_FEE);

        uint256 actual = getFee(0, address(0), defaultMultiplierBps, multiplierBps, executionFee);
        uint256 expected = (executionFee * defaultMultiplierBps) / BPS_DENOMINATOR;

        assertEq(actual, expected);
    }

    function testFuzz_getFee_useMultiplier(uint16 multiplierBps, uint256 executionFee) public {
        uint16 defaultMultiplierBps = 12000;
        multiplierBps = uint16(bound(defaultMultiplierBps, 1, MAX_MULTIPLIER_BPS));
        executionFee = bound(executionFee, MIN_EXECUTION_FEE, MAX_EXECUTION_FEE);

        uint256 actual = getFee(0, address(0), defaultMultiplierBps, multiplierBps, executionFee);
        uint256 expected = (executionFee * multiplierBps) / BPS_DENOMINATOR;

        assertEq(actual, expected);
    }
}
