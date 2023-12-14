// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Errors } from "../contracts/libs/Errors.sol";

import { LayerZeroTest } from "./utils/LayerZeroTest.sol";
import { OAppMock, ComposerMock } from "./mocks/AppMock.sol";
import { IMessagingComposer } from "../contracts/interfaces/IMessagingComposer.sol";

contract MessagingComposerTest is LayerZeroTest {
    address internal oapp;
    address internal composer;
    bytes32 internal guid;
    bytes internal message;

    function setUp() public override {
        super.setUp();
        oapp = address(new OAppMock(address(endpoint)));
        composer = OAppMock(oapp).composer();
        guid = keccak256("guid");
        message = bytes("foobar");
    }

    function test_sendCompose() public {
        vm.startPrank(oapp);

        vm.expectEmit(false, false, false, true, address(endpoint));
        emit IMessagingComposer.ComposeSent(oapp, composer, guid, 0, message);
        endpoint.sendCompose(composer, guid, 0, message);
        assertEq(endpoint.composeQueue(oapp, composer, guid, 0), keccak256(message));

        // revert due to sending same message
        vm.expectRevert(Errors.ComposeExists.selector);
        endpoint.sendCompose(composer, guid, 0, message);
    }

    function test_lzCompose() public {
        // send composed message
        vm.prank(oapp);
        endpoint.sendCompose(composer, guid, 0, message);

        // lzCompose and clear composed message
        vm.expectEmit(false, false, false, true, address(endpoint));
        emit IMessagingComposer.ComposeDelivered(oapp, composer, guid, 0);
        endpoint.lzCompose(oapp, composer, guid, 0, message, bytes(""));
        assertEq(endpoint.composeQueue(oapp, composer, guid, 0), bytes32(uint256(1))); // message marked as sent
        assertEq(ComposerMock(composer).count(), 1);

        // cant resend message even if it is marked as sent
        vm.expectRevert(Errors.ComposeExists.selector);
        vm.prank(oapp);
        endpoint.sendCompose(composer, guid, 0, message);
    }

    function test_lzComposeFail() public {
        vm.prank(address(oapp));
        bytes memory invalidMsg = bytes("Invalid message");
        endpoint.sendCompose(composer, guid, 0, invalidMsg);

        // fund the executor
        address executor = address(0xdead);
        vm.deal(executor, 100);
        vm.prank(executor);

        // mock the executor call the lzCompose() with 100 value
        // fail to receive due to app revert when the message is not "foobar"
        // payload should not be cleared and refund the value
        vm.expectRevert();
        endpoint.lzCompose{ value: 100 }(oapp, composer, guid, 0, invalidMsg, bytes(""));
        assertEq(endpoint.composeQueue(oapp, composer, guid, 0), keccak256(invalidMsg));
        assertEq(address(executor).balance, 100);
    }
}
