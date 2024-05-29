// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { AddressCast } from "../../contracts/libs/AddressCast.sol";

contract AddressCastTest is Test {
    AddressCastWrapper internal addressCastWrapper;

    function setUp() public {
        addressCastWrapper = new AddressCastWrapper();
    }

    function test_Bytes_ToBytes32() public {
        bytes memory bytesAddress = abi.encodePacked(address(0x1));
        bytes32 bytes32Address = addressCastWrapper.toBytes32(bytesAddress);
        assertEq(bytes32Address, bytes32(uint256(0x1)), "should be equal");
    }

    function test_Revert_Bytes_ToBytes32_IfGt32Bytes() public {
        bytes memory bytesAddress = abi.encodePacked(address(0x1), address(0x2));
        vm.expectRevert(AddressCast.AddressCast_InvalidAddress.selector);
        addressCastWrapper.toBytes32(bytesAddress);
    }

    function test_Address_ToBytes32() public {
        bytes32 bytes32Address = AddressCast.toBytes32(address(0x1));
        assertEq(bytes32Address, bytes32(uint256(0x1)), "should be equal");
    }

    function test_ToBytes() public {
        bytes32 bytes32Address = bytes32(uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        bytes memory bytesAddress = AddressCast.toBytes(bytes32Address, 20);
        assertEq(bytesAddress, abi.encodePacked(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF), "should be equal");

        bytesAddress = AddressCast.toBytes(bytes32Address, 1);
        assertEq(bytesAddress, abi.encodePacked(uint8(0xff)), "should be equal");

        bytesAddress = AddressCast.toBytes(bytes32Address, 2);
        assertEq(bytesAddress, abi.encodePacked(uint16(0xffff)), "should be equal");

        bytesAddress = AddressCast.toBytes(bytes32Address, 32);
        assertEq(
            bytesAddress,
            abi.encodePacked(uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)),
            "should be equal"
        );
    }

    function test_Revert_ToBytes_IfSizeGt32() public {
        bytes32 bytes32Address = bytes32(
            uint256(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
        );
        vm.expectRevert(AddressCast.AddressCast_InvalidSizeForAddress.selector);
        AddressCast.toBytes(bytes32Address, 33);
    }

    function test_Revert_ToBytes_IfSizeEq0() public {
        bytes32 bytes32Address = bytes32(
            uint256(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
        );
        vm.expectRevert(AddressCast.AddressCast_InvalidSizeForAddress.selector);
        AddressCast.toBytes(bytes32Address, 0);
    }

    function test_Bytes_ToAddress() public {
        bytes memory bytesAddress = abi.encodePacked(address(0x1));
        address addressAddress = addressCastWrapper.toAddress(bytesAddress);
        assertEq(addressAddress, address(0x1), "should be equal");
    }

    function test_Bytes32_ToAddress() public {
        bytes32 bytes32Address = bytes32(uint256(0x1));
        address addressAddress = AddressCast.toAddress(bytes32Address);
        assertEq(addressAddress, address(0x1), "should be equal");
    }
}

contract AddressCastWrapper {
    function toBytes32(bytes calldata _addressBytes) public pure returns (bytes32) {
        return AddressCast.toBytes32(_addressBytes);
    }

    function toAddress(bytes calldata _addressBytes) public pure returns (address result) {
        return AddressCast.toAddress(_addressBytes);
    }
}
