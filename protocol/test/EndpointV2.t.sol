// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AddressCast } from "../contracts/libs/AddressCast.sol";
import { MessagingFee, MessagingParams, MessagingReceipt, Origin, ILayerZeroEndpointV2 } from "../contracts/interfaces/ILayerZeroEndpointV2.sol";
import { EndpointV2 } from "../contracts/EndpointV2.sol";
import { SimpleMessageLib } from "../contracts/messagelib/SimpleMessageLib.sol";
import { Errors } from "../contracts/libs/Errors.sol";

import { LayerZeroTest } from "./utils/LayerZeroTest.sol";
import { OAppMock } from "./mocks/AppMock.sol";
import { TokenMock } from "./mocks/TokenMock.sol";

contract EndpointV2Test is LayerZeroTest {
    event LzReceiveFailed(Origin origin, address receiver, bytes reason);

    ERC20 internal lzToken;

    OAppMock internal oapp;
    address internal sender;
    bytes32 internal senderB32;
    address payable internal refundAddress;
    address internal receiver;
    bytes32 internal receiverB32;
    address internal delegate;
    bytes internal message;
    bytes32 internal guid;
    bytes internal payload;
    bytes32 internal payloadHash;

    mapping(uint64 => bool) recommittableNonces;

    function setUp() public override {
        super.setUp();
        lzToken = new TokenMock(1000);

        oapp = new OAppMock(address(endpoint));
        sender = address(this);
        senderB32 = AddressCast.toBytes32(sender);
        refundAddress = payable(address(123));
        receiver = address(oapp);
        receiverB32 = AddressCast.toBytes32(receiver);
        delegate = address(456);

        message = "foo";
        guid = keccak256("guid");
        payload = abi.encodePacked(guid, message);
        payloadHash = keccak256(payload);
    }

    function test_quote() public {
        MessagingParams memory msgParams = MessagingParams(remoteEid, bytes32(0), message, "", false);
        // quote native only
        MessagingFee memory msgFee = endpoint.quote(msgParams, sender);
        assertEq(msgFee.nativeFee, 100);
        assertEq(msgFee.lzTokenFee, 0);

        // fail to pay lz token due to endpoint not supporting lz token
        msgParams.payInLzToken = true;
        vm.expectRevert(Errors.LzTokenUnavailable.selector);
        endpoint.quote(msgParams, sender);

        // enable lz token and quote again
        endpoint.setLzToken(address(lzToken));
        msgFee = endpoint.quote(msgParams, sender);
        assertEq(msgFee.nativeFee, 100);
        assertEq(msgFee.lzTokenFee, 99);
    }

    function test_sendWithNative() public {
        MessagingParams memory msgParams = MessagingParams(remoteEid, receiverB32, message, "", false);

        // assert the PacketSent event
        vm.expectEmit(false, false, false, true, address(endpoint));
        bytes memory expectedPacket = newAndEncodePacket(1, localEid, sender, remoteEid, receiverB32, message);
        emit ILayerZeroEndpointV2.PacketSent(expectedPacket, "", address(simpleMsgLib));

        // send with 200 native, but refund 100
        MessagingReceipt memory receipt = endpoint.send{ value: 200 }(msgParams, refundAddress);
        assertEq(receipt.fee.nativeFee, 100);
        assertEq(receipt.fee.lzTokenFee, 0);

        // the balance of both msglib and refund should be 100, but endpoint should be 0
        assertEq(address(simpleMsgLib).balance, 100);
        assertEq(address(refundAddress).balance, 100);
        assertEq(address(endpoint).balance, 0);

        // fail to send with lz token
        msgParams.payInLzToken = true;
        vm.expectRevert(Errors.LzTokenUnavailable.selector);
        endpoint.send{ value: 200 }(msgParams, refundAddress);

        // fail for insufficient fee
        msgParams.payInLzToken = false;
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientFee.selector, 100, 99, 0, 0));
        endpoint.send{ value: 99 }(msgParams, refundAddress);
    }

    function test_sendWithNativeAndLzToken() public {
        // enable lz token and send lz token to endpoint
        endpoint.setLzToken(address(lzToken));
        lzToken.transfer(address(endpoint), 200);

        // send with 200 native and 200, but the endpoint only accept 100 native and 99 lz token
        MessagingParams memory msgParams = MessagingParams(remoteEid, receiverB32, message, "", true);
        MessagingReceipt memory receipt = endpoint.send{ value: 200 }(msgParams, refundAddress);
        assertEq(receipt.fee.nativeFee, 100);
        assertEq(receipt.fee.lzTokenFee, 99);

        // native balance of both msglib and refund should be 100, but endpoint should be 0
        assertEq(address(simpleMsgLib).balance, 100);
        assertEq(address(refundAddress).balance, 100);
        assertEq(address(endpoint).balance, 0);

        // lz token balance of msglib should be 99, but endpoint should be 0
        assertEq(lzToken.balanceOf(address(simpleMsgLib)), 99);
        assertEq(lzToken.balanceOf(address(endpoint)), 0);

        // fail for insufficient lz token
        lzToken.transfer(address(endpoint), 98);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientFee.selector, 100, 200, 99, 98));
        endpoint.send{ value: 200 }(msgParams, refundAddress);
    }

    function test_verify() public {
        Origin memory origin = Origin(remoteEid, senderB32, 1);

        // fail to verify by an invalid msglib
        vm.prank(address(0x1));
        vm.expectRevert(Errors.InvalidReceiveLibrary.selector);
        endpoint.verify(origin, receiver, payloadHash);

        // verifiable by a valid msglib
        bool verifiable = endpoint.verifiable(origin, receiver, address(simpleMsgLib), payloadHash);
        assertTrue(verifiable);

        vm.prank(address(simpleMsgLib));
        vm.expectEmit(false, false, false, true, address(endpoint));
        emit ILayerZeroEndpointV2.PacketVerified(origin, receiver, payloadHash);
        endpoint.verify(origin, receiver, payloadHash);
        assertEq(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1), payloadHash);

        // re-verify different payload with same nonce
        bytes32 newPayloadHash = keccak256("newPayload");
        verifiable = endpoint.verifiable(origin, receiver, address(simpleMsgLib), payloadHash);
        assertTrue(verifiable);
        vm.prank(address(simpleMsgLib));
        endpoint.verify(origin, receiver, newPayloadHash);
        assertEq(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1), newPayloadHash);
    }

    function test_lzReceive() public {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));

        // receive and clear payload
        vm.expectEmit(false, false, false, true, address(endpoint));
        emit ILayerZeroEndpointV2.PacketDelivered(origin, receiver);
        endpoint.lzReceive(origin, receiver, guid, message, "");
        assertFalse(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));
    }

    // This test should cover *all* cases where a payload hash can and cannot be recommitted to the messaging channel
    function test_recommitVerification() public {
        /* Populate the channel first
           1      | 2       | 3        | 4        | 5         | 6        | 7
           Burned | Skipped | Nilified | Verified | Executed  | Verified | Nilified
                  |         |          |          | LazyNonce |          | InboundNonce
        */
        vm.startPrank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);

        vm.startPrank(receiver);
        endpoint.skip(receiver, remoteEid, senderB32, 2);
        endpoint.nilify(receiver, remoteEid, senderB32, 3, bytes32(0x0));

        vm.startPrank(address(simpleMsgLib));
        origin = Origin(remoteEid, senderB32, 4);
        endpoint.verify(origin, receiver, payloadHash);
        origin = Origin(remoteEid, senderB32, 5);
        endpoint.verify(origin, receiver, payloadHash);
        endpoint.lzReceive(origin, receiver, guid, message, "");
        origin = Origin(remoteEid, senderB32, 6);
        endpoint.verify(origin, receiver, payloadHash);

        vm.startPrank(receiver);
        endpoint.nilify(receiver, remoteEid, senderB32, 7, bytes32(0x0));
        endpoint.burn(receiver, remoteEid, senderB32, 1, payloadHash);

        vm.stopPrank();

        // Exactly-once delivery: cannot recommit an executed or skipped nonce
        // All other nonces should be recommittable
        recommittableNonces[1] = false;
        recommittableNonces[2] = false;
        recommittableNonces[3] = true;
        recommittableNonces[4] = true;
        recommittableNonces[5] = false;
        recommittableNonces[6] = true;
        recommittableNonces[7] = true;
        recommittableNonces[8] = true;
        for (uint64 _nonce = 0; _nonce <= 8; ++_nonce) {
            vm.prank(address(simpleMsgLib));
            origin = Origin(remoteEid, senderB32, _nonce);
            if (!recommittableNonces[_nonce]) {
                vm.expectRevert(Errors.PathNotVerifiable.selector);
            }
            endpoint.verify(origin, receiver, payloadHash);
        }
    }

    function test_initializePathway() public {
        // Temporarily blacklist the pathway before any messages are sent
        oapp.blacklistPathway(remoteEid, senderB32);

        vm.startPrank(address(simpleMsgLib));
        Origin memory originNonceOne = Origin(remoteEid, senderB32, 1);
        Origin memory originNonceTwo = Origin(remoteEid, senderB32, 2);
        // Pathway cannot verify the first nonce until OApp returns allowInitializePath = true
        vm.expectRevert(Errors.PathNotInitializable.selector);
        endpoint.verify(originNonceOne, receiver, payloadHash);

        // Pathway can verify the first nonce now that OApp returned allowInitializePath = true
        oapp.unBlacklistPathway(remoteEid, senderB32);
        endpoint.verify(originNonceOne, receiver, payloadHash);

        oapp.blacklistPathway(remoteEid, senderB32);
        vm.expectRevert(Errors.PathNotInitializable.selector);
        endpoint.verify(originNonceOne, receiver, payloadHash);

        // Pathway cannot be "closed" once one (or more) nonces have been executed
        endpoint.lzReceive(originNonceOne, receiver, guid, message, "");
        endpoint.verify(originNonceTwo, receiver, payloadHash);
    }

    function test_lzReceiveFail() public {
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        bytes memory invalidMsg = bytes("Invalid message");
        bytes32 invalidPayloadHash = keccak256(abi.encodePacked(guid, invalidMsg));

        // verify an invalid payload
        endpoint.verify(origin, receiver, invalidPayloadHash);
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));

        // fund the executor
        address executor = address(0xdead);
        vm.deal(executor, 100);
        vm.prank(executor);

        // mock the executor call the lzReceive() with 100 value
        // fail to receive due to app revert when the message is not "foo"
        // payload should not be cleared and refund the value
        vm.expectRevert();
        endpoint.lzReceive{ value: 100 }(origin, receiver, guid, invalidMsg, "");
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));
        assertEq(address(executor).balance, 100);
    }

    function _test_clear(address _delegate) internal {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));

        // clear payload
        vm.prank(_delegate);
        vm.expectEmit(false, false, false, true, address(endpoint));
        emit ILayerZeroEndpointV2.PacketDelivered(origin, receiver);
        endpoint.clear(receiver, origin, guid, message);
    }

    function test_clear() public {
        _test_clear(receiver);
    }

    function test_clear_delegated() public {
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));
        vm.prank(delegate);
        vm.expectRevert(Errors.Unauthorized.selector);
        endpoint.clear(receiver, origin, guid, message);

        vm.prank(receiver);
        endpoint.setDelegate(delegate);
        _test_clear(delegate);
    }

    function test_clear_undelegated() public {
        vm.prank(receiver);
        endpoint.setDelegate(delegate);
        _test_clear(receiver);
    }

    function test_setLzToken() public {
        assertEq(endpoint.lzToken(), address(0x0));
        endpoint.setLzToken(address(lzToken));
        assertEq(endpoint.lzToken(), address(lzToken));

        vm.prank(address(1)); // invalid owner
        vm.expectRevert(); // not owner revert
        endpoint.setLzToken(address(0));
    }
}
