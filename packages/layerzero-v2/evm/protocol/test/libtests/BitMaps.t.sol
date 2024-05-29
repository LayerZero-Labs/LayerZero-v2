// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { BitMap256, BitMaps } from "../../contracts/messagelib/libs/BitMaps.sol";

contract BitMapsTest is Test {
    function test_set(uint8 keyA, uint8 keyB, uint8 keyC) public {
        vm.assume(keyA != keyB && keyA != keyC && keyB != keyC);

        BitMap256 bitmap;

        bitmap = BitMaps.set(bitmap, keyA);
        bitmap = BitMaps.set(bitmap, keyB);
        assertEq(BitMaps.get(bitmap, keyA), true);
        assertEq(BitMaps.get(bitmap, keyB), true);
        assertEq(BitMaps.get(bitmap, keyC), false);
    }

    function test_set0() public {
        BitMap256 bitmap;
        assertFalse(BitMaps.get(bitmap, 0));
        bitmap = BitMaps.set(bitmap, 0);
        assertTrue(BitMaps.get(bitmap, 0));
    }

    function test_setMax() public {
        BitMap256 bitmap;
        assertFalse(BitMaps.get(bitmap, type(uint8).max));
        bitmap = BitMaps.set(bitmap, type(uint8).max);
        assertTrue(BitMaps.get(bitmap, type(uint8).max));
    }
}
