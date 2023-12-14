// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ISendLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { Worker } from "../contracts/Worker.sol";
import { TokenMock } from "./mocks/TokenMock.sol";

contract WorkerTest is Worker, Test {
    address internal ROLE_ADMIN = address(0x1);
    address internal ADMIN = address(0x2);

    constructor() Worker(new address[](0), address(0), 0, ROLE_ADMIN, new address[](0)) {
        _grantRole(ADMIN_ROLE, ADMIN);
    }

    function test_hasAcl() public {
        address alice = address(0xabc);
        address bob = address(0xdef);

        // both allowlist and denylist are empty, so everyone is allowed
        assertEq(hasAcl(alice), true);
        assertEq(hasAcl(bob), true);

        // add alice to denylist, so she is not allowed, but bob is still allowed
        _grantRole(DENYLIST, alice);
        assertEq(hasAcl(alice), false);
        assertEq(hasAcl(bob), true);

        // add alice to allowlist, but she is still not allowed because she is in the denylist
        // for bob, he is not allowed because he is not in the allowlist
        _grantRole(ALLOWLIST, alice);
        assertEq(hasAcl(alice), false);
        assertEq(hasAcl(bob), false);

        // add bob to allowlist, so he is allowed
        _grantRole(ALLOWLIST, bob);
        assertEq(hasAcl(bob), true);

        // remove alice from denylist, so she is allowed
        _revokeRole(DENYLIST, alice);
        assertEq(hasAcl(alice), true);

        // remove alice and bob from allowlist, so both allowlist and denylist are empty again
        _revokeRole(ALLOWLIST, alice);
        _revokeRole(ALLOWLIST, bob);
        assertEq(hasAcl(alice), true);
        assertEq(hasAcl(bob), true);
    }

    function test_setPaused() public {
        // only role admin can set paused
        vm.expectRevert();
        this.setPaused(true);

        vm.startPrank(ROLE_ADMIN);
        this.setPaused(true);
        assertEq(paused(), true);
        this.setPaused(false);
        assertEq(paused(), false);
    }

    function test_setPriceFeed() public {
        // only admin can set price feed
        vm.expectRevert();
        this.setPriceFeed(address(1234));

        vm.startPrank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit SetPriceFeed(address(1234));
        this.setPriceFeed(address(1234));
        assertEq(priceFeed, address(1234));
    }

    function test_setWorkerFeeLib() public {
        // only admin can set worker fee lib
        vm.expectRevert();
        this.setWorkerFeeLib(address(1234));

        vm.startPrank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit SetWorkerLib(address(1234));
        this.setWorkerFeeLib(address(1234));
        assertEq(workerFeeLib, address(1234));
    }

    function test_setDefaultMultiplierBps() public {
        // only admin can set default multiplier bps
        vm.expectRevert();
        this.setDefaultMultiplierBps(10);

        vm.startPrank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit SetDefaultMultiplierBps(10);
        this.setDefaultMultiplierBps(10);
        assertEq(defaultMultiplierBps, 10);
    }

    function test_withdrawFee() public {
        address lib = address(0x1234);
        address to = address(0x5678);
        vm.mockCall(lib, abi.encodeWithSelector(ISendLib.withdrawFee.selector), "");

        // only admin can withdraw fee
        vm.expectRevert();
        this.withdrawFee(lib, to, 10);

        // lib must have the message lib role
        vm.startPrank(ADMIN);
        vm.expectRevert(OnlyMessageLib.selector);
        this.withdrawFee(lib, to, 10);

        // grant lib the message lib role
        _grantRole(MESSAGE_LIB_ROLE, lib);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(lib, to, 10);
        this.withdrawFee(lib, to, 10);
    }

    function test_withdrawToken() public {
        address alice = address(0xabc);
        TokenMock token = new TokenMock();

        // only admin can withdraw token
        vm.expectRevert();
        this.withdrawToken(address(token), alice, 10);

        vm.startPrank(ADMIN);
        // withdraw token
        this.withdrawToken(address(token), alice, 10);
        assertEq(token.balanceOf(address(alice)), 10);

        // withdraw native
        this.withdrawToken(address(0x0), alice, 10);
        assertEq(address(alice).balance, 10);
    }

    function test_grantAndRevokeRole() public {
        address alice = address(0xabc);
        address bob = address(0xdef);

        // grant ALLOWLIST role to alice, allowlistSize should be 1
        _grantRole(ALLOWLIST, alice);
        assertEq(allowlistSize, 1);

        // grant ALLOWLIST role to bob, allowlistSize should be 2
        _grantRole(ALLOWLIST, bob);
        assertEq(allowlistSize, 2);

        // grant ALLOWLIST role to alice again, allowlistSize should still be 2
        _grantRole(ALLOWLIST, alice);
        assertEq(allowlistSize, 2);

        // grant DENYLIST role to alice, allowlistSize should still be 2
        _grantRole(DENYLIST, alice);
        assertEq(allowlistSize, 2);

        // revoke ALLOWLIST role from alice, allowlistSize should be 1
        _revokeRole(ALLOWLIST, alice);
        assertEq(allowlistSize, 1);

        // revoke ALLOWLIST role from bob, allowlistSize should be 0
        _revokeRole(ALLOWLIST, bob);
        assertEq(allowlistSize, 0);
    }
}
