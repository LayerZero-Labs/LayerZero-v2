// SPDX-License-Identifier: MIT

// modified from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/BitMaps.sol
pragma solidity ^0.8.20;

type BitMap256 is uint256;

using BitMaps for BitMap256 global;

library BitMaps {
    /**
     * @dev Returns whether the bit at `index` is set.
     */
    function get(BitMap256 bitmap, uint8 index) internal pure returns (bool) {
        uint256 mask = 1 << index;
        return BitMap256.unwrap(bitmap) & mask != 0;
    }

    /**
     * @dev Sets the bit at `index`.
     */
    function set(BitMap256 bitmap, uint8 index) internal pure returns (BitMap256) {
        uint256 mask = 1 << index;
        return BitMap256.wrap(BitMap256.unwrap(bitmap) | mask);
    }
}
