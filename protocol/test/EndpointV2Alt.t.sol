// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AddressCast } from "../contracts/libs/AddressCast.sol";
import { MessagingFee, MessagingParams, MessagingReceipt, Origin } from "../contracts/interfaces/ILayerZeroEndpointV2.sol";
import { EndpointV2Alt } from "../contracts/EndpointV2Alt.sol";
import { SimpleMessageLib } from "../contracts/messagelib/SimpleMessageLib.sol";
import { Errors } from "../contracts/libs/Errors.sol";

import { LayerZeroTest } from "./utils/LayerZeroTest.sol";
import { OAppMock } from "./mocks/AppMock.sol";
import { TokenMock } from "./mocks/TokenMock.sol";

contract EndpointV2AltTest is LayerZeroTest {
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);

    // endpoint2 is the endpoint with alt token
    EndpointV2Alt internal endpointAlt;
    SimpleMessageLib internal simpleMsgLibAlt;

    ERC20 internal altToken;
    ERC20 internal lzToken;

    OAppMock internal oapp;
    address payable internal refundAddress;
    address internal receiver;
    bytes32 internal receiverB32;
    bytes internal message;

    function setUp() public override {
        super.setUp();
        lzToken = new TokenMock(1000);
        altToken = new TokenMock(1000);

        endpointAlt = setupEndpointAlt(localEid, address(altToken));
        simpleMsgLibAlt = setupSimpleMessageLib(address(endpointAlt), remoteEid, true);
        receiver = address(oapp);
        receiverB32 = AddressCast.toBytes32(receiver);
        message = "foo";
        refundAddress = payable(address(123));
    }

    function test_Send_WithAlt() public {
        // send with 200 alt, but only accept 100 alt
        altToken.transfer(address(endpointAlt), 200);
        MessagingParams memory msgParams = MessagingParams(remoteEid, receiverB32, message, "", false);
        MessagingReceipt memory receipt = endpointAlt.send(msgParams, refundAddress);
        assertEq(receipt.fee.nativeFee, 100);
        assertEq(receipt.fee.lzTokenFee, 0);

        // alt token balance of msglib is 100, but endpoint should be 0
        assertEq(altToken.balanceOf(address(simpleMsgLibAlt)), 100);
        assertEq(altToken.balanceOf(address(endpointAlt)), 0);
        assertEq(altToken.balanceOf(address(refundAddress)), 100);

        // fail for insufficient fee
        altToken.transfer(address(endpointAlt), 99);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientFee.selector, 100, 99, 0, 0));
        endpointAlt.send(msgParams, refundAddress);

        // fail for sending with value
        altToken.transfer(address(endpointAlt), 100);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyAltToken.selector));
        endpointAlt.send{ value: 1 }(msgParams, refundAddress);
    }
}
