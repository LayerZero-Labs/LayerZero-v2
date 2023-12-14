// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { AddressSizeConfig } from "../contracts/uln/uln301/AddressSizeConfig.sol";

contract AddressSizeConfigTest is AddressSizeConfig, Test {
    function test_setAddressSize() public {
        vm.startPrank(owner());

        // can not set address size more than 32
        vm.expectRevert(InvalidAddressSize.selector);
        this.setAddressSize(1, 33);

        this.setAddressSize(1, 32);
        assertEq(addressSizes[1], 32);

        // can not set address size twice
        vm.expectRevert(AddressSizeAlreadySet.selector);
        this.setAddressSize(1, 31);
    }
}
