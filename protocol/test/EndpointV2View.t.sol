// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import "./utils/LayerZeroTest.sol";
import "./mocks/AppMock.sol";
import "../contracts/EndpointV2View.sol";

contract EndpointV2ViewTest is LayerZeroTest {
    using AddressCast for address;

    bytes32 public constant NIL_PAYLOAD_HASH = bytes32(type(uint256).max);

    OAppMock internal oapp;
    bytes32 internal senderB32;
    address internal receiver;
    bytes internal message;
    bytes32 internal guid;
    bytes32 internal payloadHash;

    EndpointV2View internal endpointView;

    function setUp() public override {
        super.setUp();
        oapp = new OAppMock(address(endpoint));
        senderB32 = address(this).toBytes32();
        receiver = address(oapp);
        message = "foo";
        guid = keccak256("guid");
        payloadHash = keccak256(abi.encodePacked(guid, message));

        endpointView = new EndpointV2View();
        endpointView.initialize(address(endpoint));
    }

    function test_Executable_NotExecutable() public {
        // not verified
        assertEq(
            uint256(endpointView.executable(Origin(remoteEid, senderB32, 1), receiver)),
            uint256(ExecutionState.NotExecutable)
        );
    }

    function test_Executable_VerifiedButNotExecutable() public {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 2);
        endpoint.verify(origin, receiver, payloadHash);

        // verified
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 2) != bytes32(0));

        // not executable, since only nonce 2 is verified and nonce 1 is not
        assertEq(uint256(endpointView.executable(origin, receiver)), uint256(ExecutionState.VerifiedButNotExecutable));
    }

    function test_Executable_NotExecutable_NilPayloadHash() public {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 2);
        endpoint.verify(origin, receiver, payloadHash);
        vm.prank(receiver);
        endpoint.nilify(receiver, origin.srcEid, origin.sender, origin.nonce, payloadHash);

        // verified
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 2) != bytes32(0));

        // not executable and not verified
        assertEq(uint256(endpointView.executable(origin, receiver)), uint256(ExecutionState.NotExecutable));
    }

    function test_Executable_Executable() public {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);

        // verified
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));

        assertEq(uint256(endpointView.executable(origin, receiver)), uint256(ExecutionState.Executable));
    }

    function test_Executable_Executed() public {
        // verify a payload to receive
        vm.prank(address(simpleMsgLib));
        Origin memory origin = Origin(remoteEid, senderB32, 1);
        endpoint.verify(origin, receiver, payloadHash);

        // verified
        assertTrue(endpoint.inboundPayloadHash(receiver, remoteEid, senderB32, 1) != bytes32(0));

        // execute
        endpoint.lzReceive(origin, receiver, guid, message, "");

        assertEq(uint256(endpointView.executable(origin, receiver)), uint256(ExecutionState.Executed));
    }
}
