// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { MessagingContext } from "../contracts/MessagingContext.sol";

contract MessagingContextTest is Test, MessagingContext {
    function test_sendContext() public {
        // send context
        send(1, address(0x123));

        // no send context after send()
        assertFalse(isSendingMessage());
        (uint32 dstEid, address sender) = this.getSendContext();
        assertEq(dstEid, 0);
        assertEq(sender, address(0));
    }

    function send(uint32 _dstEid, address _sender) public sendContext(_dstEid, _sender) {
        assertTrue(isSendingMessage());
        (uint32 dstEid, address sender) = this.getSendContext();
        assertEq(dstEid, _dstEid);
        assertEq(sender, _sender);
    }
}
