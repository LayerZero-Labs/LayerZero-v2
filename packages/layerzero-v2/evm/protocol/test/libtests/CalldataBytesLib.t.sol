// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { CalldataBytesLib } from "../../contracts/libs/CalldataBytesLib.sol";

contract CalldataBytesLibTest is Test {
    bytes internal constant BYTES = hex"1234567890123456789012345678901234567890123456789012345678901234567890";

    function test_toU8() public {
        uint8 v = CalldataBytesLibWrapper.toU8(BYTES, 0);
        assertEq(v, uint8(0x12));
    }

    function test_toU16() public {
        uint16 v = CalldataBytesLibWrapper.toU16(BYTES, 0);
        assertEq(v, uint16(0x1234));
    }

    function test_toU32() public {
        uint32 v = CalldataBytesLibWrapper.toU32(BYTES, 0);
        assertEq(v, uint32(0x12345678));
    }

    function test_toU64() public {
        uint64 v = CalldataBytesLibWrapper.toU64(BYTES, 0);
        assertEq(v, uint64(0x1234567890123456));
    }

    function test_toU128() public {
        uint128 v = CalldataBytesLibWrapper.toU128(BYTES, 0);
        assertEq(v, uint128(0x12345678901234567890123456789012));
    }

    function test_toU256() public {
        uint256 v = CalldataBytesLibWrapper.toU256(BYTES, 0);
        assertEq(v, uint256(0x1234567890123456789012345678901234567890123456789012345678901234));
    }

    function test_toAddr() public {
        address v = CalldataBytesLibWrapper.toAddr(BYTES, 0);
        assertEq(v, address(0x1234567890123456789012345678901234567890));
    }

    function test_toB32() public {
        bytes32 v = CalldataBytesLibWrapper.toB32(BYTES, 0);
        assertEq(v, bytes32(0x1234567890123456789012345678901234567890123456789012345678901234));
    }
}

/// @dev A wrapper of CalldataBytesLibWrapper to expose internal functions for calldata params
library CalldataBytesLibWrapper {
    function toU8(bytes calldata _bytes, uint256 _start) external pure returns (uint8) {
        return CalldataBytesLib.toU8(_bytes, _start);
    }

    function toU16(bytes calldata _bytes, uint256 _start) external pure returns (uint16) {
        return CalldataBytesLib.toU16(_bytes, _start);
    }

    function toU32(bytes calldata _bytes, uint256 _start) external pure returns (uint32) {
        return CalldataBytesLib.toU32(_bytes, _start);
    }

    function toU64(bytes calldata _bytes, uint256 _start) external pure returns (uint64) {
        return CalldataBytesLib.toU64(_bytes, _start);
    }

    function toU128(bytes calldata _bytes, uint256 _start) external pure returns (uint128) {
        return CalldataBytesLib.toU128(_bytes, _start);
    }

    function toU256(bytes calldata _bytes, uint256 _start) external pure returns (uint256) {
        return CalldataBytesLib.toU256(_bytes, _start);
    }

    function toAddr(bytes calldata _bytes, uint256 _start) external pure returns (address) {
        return CalldataBytesLib.toAddr(_bytes, _start);
    }

    function toB32(bytes calldata _bytes, uint256 _start) external pure returns (bytes32) {
        return CalldataBytesLib.toB32(_bytes, _start);
    }
}
