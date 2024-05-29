// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";

import { TreasuryFeeHandler } from "../contracts/uln/uln301/TreasuryFeeHandler.sol";

import { TokenMock } from "./mocks/TokenMock.sol";

contract TreasuryFeeHandlerTest is Test {
    address internal endpoint = address(0x1234);
    address internal msglib = address(0x5678);
    address internal sender = address(0x9abc);
    address internal treasury = address(0xdef0);
    TokenMock internal lzToken;
    TreasuryFeeHandler internal handler;

    function setUp() public {
        handler = new TreasuryFeeHandler(endpoint);
        lzToken = new TokenMock();
    }

    function test_payFee() public {
        lzToken.transfer(sender, 100);
        vm.prank(sender);
        lzToken.approve(address(handler), 100);

        vm.startPrank(msglib);

        // if the msglib is set by the sender but not sending payload, revert
        vm.mockCall(
            endpoint,
            abi.encodeWithSelector(ILayerZeroEndpoint.getSendLibraryAddress.selector),
            abi.encode(msglib)
        );
        vm.mockCall(endpoint, abi.encodeWithSelector(ILayerZeroEndpoint.isSendingPayload.selector), abi.encode(false));
        vm.expectRevert(TreasuryFeeHandler.LZ_TreasuryFeeHandler_OnlyOnSending.selector);
        handler.payFee(address(lzToken), sender, 100, 100, treasury);

        // when both conditions are met, but required amount is more than supplied, revert
        vm.mockCall(endpoint, abi.encodeWithSelector(ILayerZeroEndpoint.isSendingPayload.selector), abi.encode(true));
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryFeeHandler.LZ_TreasuryFeeHandler_InvalidAmount.selector, 100, 99)
        );
        handler.payFee(address(lzToken), sender, 100, 99, treasury);

        // when both conditions are met, and required amount is less than supplied, transfer
        handler.payFee(address(lzToken), sender, 100, 100, treasury);
        assertEq(lzToken.balanceOf(treasury), 100);
        assertEq(lzToken.balanceOf(sender), 0);
    }
}
