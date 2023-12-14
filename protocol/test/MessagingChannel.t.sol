// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { AddressCast } from "../contracts/libs/AddressCast.sol";
import { Errors } from "../contracts/libs/Errors.sol";
import { MessagingChannel } from "../contracts/MessagingChannel.sol";

contract MessagingChannelTest is Test, MessagingChannel {
    mapping(address oapp => address delegate) public delegates;

    uint32 internal remoteEid;
    address internal sender;
    bytes32 internal senderB32;
    address internal receiver;
    bytes32 internal receiverB32;
    address internal delegate;

    bytes internal message;
    bytes32 internal guid;
    bytes internal payload;
    bytes32 internal payloadHash;

    constructor() MessagingChannel(1) {
        remoteEid = 1;
        sender = address(0x123);
        senderB32 = AddressCast.toBytes32(sender);
        receiver = address(0x456);
        receiverB32 = AddressCast.toBytes32(receiver);
        delegate = address(0x789);

        message = "foo";
        guid = keccak256("guid");
        payload = abi.encodePacked(guid, message);
        payloadHash = keccak256(payload);
    }

    function test_outbound() public {
        // nonce 1
        uint64 nonce = _outbound(sender, remoteEid, receiverB32);
        assertEq(nonce, 1);
        assertEq(outboundNonce[sender][remoteEid][receiverB32], 1);

        // nonce 2
        nonce = _outbound(sender, remoteEid, receiverB32);
        assertEq(nonce, 2);
        assertEq(outboundNonce[sender][remoteEid][receiverB32], 2);
    }

    function test_Inbound_Revert_InvalidPayloadHash() public {
        // revert due to invalid payload hash
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidPayloadHash.selector));
        _inbound(receiver, remoteEid, senderB32, 1, bytes32(0x0));
    }

    function test_inbound() public {
        _inbound(receiver, remoteEid, senderB32, 1, payloadHash);
        assertTrue(_hasPayloadHash(receiver, remoteEid, senderB32, 1));
        assertEq(inboundPayloadHash[receiver][remoteEid][senderB32][1], payloadHash);
    }

    function test_inboundNonce() public {
        // the initial inbound nonce is 0
        uint64 inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 0);

        // inbound with nonce 1
        _inbound(receiver, remoteEid, senderB32, 1, payloadHash);
        inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 1);

        // inbound with nonce 5, but the inbound nonce is still 1
        _inbound(receiver, remoteEid, senderB32, 5, payloadHash);
        inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 1);

        // inbound with nonce 3, but the inbound nonce is still 1
        _inbound(receiver, remoteEid, senderB32, 3, payloadHash);
        inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 1);

        // after inbound nonce 2, the inbound nonce is 3
        _inbound(receiver, remoteEid, senderB32, 2, payloadHash);
        inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 3);

        // after inbound nonce 4, the inbound nonce is 5
        _inbound(receiver, remoteEid, senderB32, 4, payloadHash);
        inBoundNonce = inboundNonce(receiver, remoteEid, senderB32);
        assertEq(inBoundNonce, 5);
    }

    function _test_skip(address _delegate) internal {
        // skip next nonce 1, and the lazyInboundNonce should become 1
        vm.startPrank(_delegate);
        vm.expectEmit(false, false, false, true);
        emit InboundNonceSkipped(remoteEid, senderB32, receiver, 1);
        this.skip(receiver, remoteEid, senderB32, 1);
        assert(lazyInboundNonce[receiver][remoteEid][senderB32] == 1);

        uint64 inboundNonce = this.inboundNonce(receiver, remoteEid, senderB32);
        // fail to skip with an invalid nonce
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, uint64(inboundNonce + 2)));
        this.skip(receiver, remoteEid, senderB32, inboundNonce + 2);
    }

    function test_skip() public {
        _test_skip(receiver);
    }

    function test_skip_delegated() public {
        // Test that the delegate cannot skip before receiver sets delegate
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        this.skip(receiver, remoteEid, senderB32, 1);
        // Set delegate
        vm.prank(receiver);
        this.setDelegate(delegate);
        // skip next nonce 1, and the lazyInboundNonce should become 1
        _test_skip(delegate);
    }

    function test_skip_undelegated() public {
        // Set delegate
        vm.prank(receiver);
        this.setDelegate(delegate);
        _test_skip(receiver);
    }

    function _test_nilify(address _delegate) internal {
        vm.startPrank(_delegate);

        // Nilify an unverified nonce should succeed
        uint64 curNonce = 1;
        vm.expectEmit(false, false, false, true);
        emit PacketNilified(
            remoteEid,
            senderB32,
            receiver,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );
        this.nilify(
            receiver,
            remoteEid,
            senderB32,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );

        // Nilify should revert with PayloadHashNotFound if the provided payload hash does not match the contents of inboundPayloadHash
        bytes32 wrongPayloadHash = bytes32(uint256(payloadHash) + 1);
        _inbound(receiver, remoteEid, senderB32, curNonce, payloadHash);
        vm.expectRevert(abi.encodeWithSelector(Errors.PayloadHashNotFound.selector, payloadHash, wrongPayloadHash));
        this.nilify(receiver, remoteEid, senderB32, curNonce, wrongPayloadHash);

        // Nilify a verified but non-executed nonce should succeed
        _inbound(receiver, remoteEid, senderB32, curNonce, payloadHash);
        vm.expectEmit(false, false, false, true);
        emit PacketNilified(
            remoteEid,
            senderB32,
            receiver,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );
        this.nilify(
            receiver,
            remoteEid,
            senderB32,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );

        // Nilify an executed nonce should revert with InvalidNonce
        curNonce = 2;
        _inbound(receiver, remoteEid, senderB32, curNonce, payloadHash);
        _clearPayload(receiver, remoteEid, senderB32, curNonce, payload);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, curNonce));
        this.nilify(
            receiver,
            remoteEid,
            senderB32,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );

        uint64 lazyNonce = lazyInboundNonce[receiver][remoteEid][senderB32];
        assertEq(lazyNonce, curNonce);

        // Nilify a non-executed nonce lower than lazyInboundNonce should succeed
        curNonce = 1;
        _inbound(receiver, remoteEid, senderB32, curNonce, payloadHash);
        _clearPayload(receiver, remoteEid, senderB32, curNonce, payload);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, curNonce));
        this.nilify(
            receiver,
            remoteEid,
            senderB32,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );

        // Nilify should work on any nonce greater than lazy inbound nonce
        curNonce = type(uint64).max;
        vm.expectEmit(false, false, false, true);
        emit PacketNilified(
            remoteEid,
            senderB32,
            receiver,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );
        this.nilify(
            receiver,
            remoteEid,
            senderB32,
            curNonce,
            inboundPayloadHash[receiver][remoteEid][senderB32][curNonce]
        );
    }

    function test_nilify() public {
        _test_nilify(receiver);
    }

    function test_nilify_delegated() public {
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        this.nilify(receiver, remoteEid, senderB32, 1, inboundPayloadHash[receiver][remoteEid][senderB32][1]);
        vm.prank(receiver);
        this.setDelegate(delegate);
        _test_nilify(delegate);
    }

    function test_nilify_undelegated() public {
        vm.prank(receiver);
        this.setDelegate(delegate);
        _test_nilify(receiver);
    }

    function _test_burn(address _delegate) internal {
        /*
        1        | 2        | 3         | 4
        verified | executed | executed  | verified
                 |          | lazyNonce |
        */
        vm.startPrank(_delegate);

        for (uint64 _nonce = 1; _nonce <= 4; ++_nonce) {
            _inbound(receiver, remoteEid, senderB32, _nonce, payloadHash);
        }
        uint64 lazyNonce = 3;
        _clearPayload(receiver, remoteEid, senderB32, lazyNonce - 1, payload);
        _clearPayload(receiver, remoteEid, senderB32, lazyNonce, payload);
        assertEq(lazyNonce, this.lazyInboundNonce(receiver, remoteEid, senderB32));

        // Burn should revert with InvalidNonce if the requested nonce is greater than lazyInboundNonce
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, lazyNonce + 1));
        this.burn(receiver, remoteEid, senderB32, lazyNonce + 1, payloadHash);

        // Burn should revert with InvalidNonce if the payload hash of the requested nonce is 0x0
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, lazyNonce - 1));
        this.burn(receiver, remoteEid, senderB32, lazyNonce - 1, EMPTY_PAYLOAD_HASH);

        // Burn should revert with PayloadHashNotFound if the provided payload hash does not match the contents of inboundPayloadHash
        bytes32 wrongPayloadHash = bytes32(uint256(payloadHash) + 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.PayloadHashNotFound.selector, payloadHash, wrongPayloadHash));
        this.burn(receiver, remoteEid, senderB32, 1, wrongPayloadHash);

        // Burn a verified but non-executed nonce should succeed
        vm.expectEmit(false, false, false, true);
        emit PacketBurnt(remoteEid, senderB32, receiver, 1, payloadHash);
        this.burn(receiver, remoteEid, senderB32, 1, payloadHash);
        assertFalse(_hasPayloadHash(receiver, remoteEid, senderB32, 1));
    }

    function test_burn() public {
        _test_burn(receiver);
    }

    function test_burn_delegated() public {
        vm.prank(delegate);
        vm.expectRevert(Errors.Unauthorized.selector);
        this.burn(receiver, remoteEid, senderB32, 1, inboundPayloadHash[receiver][remoteEid][senderB32][1]);
        vm.prank(receiver);
        this.setDelegate(delegate);
        _test_burn(delegate);
    }

    function test_burn_undelegated() public {
        vm.prank(receiver);
        this.setDelegate(delegate);
        _test_burn(receiver);
    }

    function test_clear() public {
        // verify nonce 1, 2, 4
        _inbound(receiver, remoteEid, senderB32, 1, payloadHash);
        _inbound(receiver, remoteEid, senderB32, 2, payloadHash);
        _inbound(receiver, remoteEid, senderB32, 4, payloadHash);

        // try to clear nonce 4 but fails due to nonce 3 not inbounded
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidNonce.selector, uint64(3)));
        _clearPayload(receiver, remoteEid, senderB32, 4, payload);

        // clear nonce 2 successfully
        _clearPayload(receiver, remoteEid, senderB32, 2, payload);

        // verify nonce 3
        _inbound(receiver, remoteEid, senderB32, 3, payloadHash);

        // clear nonce 4 successfully
        _clearPayload(receiver, remoteEid, senderB32, 4, payload);
    }

    function test_clearInvalidPayload() public {
        // verify nonce 1;
        _inbound(receiver, remoteEid, senderB32, 1, payloadHash);

        // reverts due to wrong message
        vm.expectRevert(abi.encodeWithSelector(Errors.PayloadHashNotFound.selector, payloadHash, keccak256("bar")));
        _clearPayload(receiver, remoteEid, senderB32, 1, "bar"); // wrong message
    }

    function test_clearTwice() public {
        // verify nonce 1;
        _inbound(receiver, remoteEid, senderB32, 1, payloadHash);

        // clears successfully
        _clearPayload(receiver, remoteEid, senderB32, 1, payload);

        // reverts due to already cleared
        vm.expectRevert(abi.encodeWithSelector(Errors.PayloadHashNotFound.selector, bytes32(0x0), payloadHash));
        _clearPayload(receiver, remoteEid, senderB32, 1, payload);
    }

    function test_nextGuid() public {
        address senderAddr = address(this);
        bytes32 expectedGuid = keccak256(
            abi.encodePacked(uint64(1), eid, AddressCast.toBytes32(senderAddr), remoteEid, receiverB32)
        );
        bytes32 actualGuid = this.nextGuid(senderAddr, remoteEid, receiverB32);
        assertEq(actualGuid, expectedGuid);
    }

    function setDelegate(address _delegate) public {
        delegates[msg.sender] = _delegate;
    }

    function _assertAuthorized(address _oapp) internal view override {
        if (msg.sender != _oapp && msg.sender != delegates[_oapp]) revert Errors.Unauthorized();
    }
}
