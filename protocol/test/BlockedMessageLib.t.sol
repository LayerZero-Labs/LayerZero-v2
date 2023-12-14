// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { AddressCast } from "../contracts/libs/AddressCast.sol";
import { MessagingParams } from "../contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Errors } from "../contracts/libs/Errors.sol";

import { LayerZeroTest } from "./utils/LayerZeroTest.sol";

contract BlockedMessageLibTest is LayerZeroTest {
    function setUp() public override {
        super.setUp();
        setDefaultMsgLib(endpoint, blockedLibrary, remoteEid);
    }

    function test_Revert_Send() public {
        address payable receiver = payable(address(0x1));
        MessagingParams memory msgParams = MessagingParams(
            remoteEid,
            AddressCast.toBytes32(receiver),
            abi.encodePacked("message"),
            "0x",
            false
        );
        vm.expectRevert(Errors.NotImplemented.selector);
        endpoint.send{ value: 101 }(msgParams, receiver);
    }

    function test_Revert_Quote() public {
        address sender = address(0x1);
        MessagingParams memory msgParams = MessagingParams(remoteEid, bytes32(0), "", "", false);
        vm.expectRevert(Errors.NotImplemented.selector);
        endpoint.quote(msgParams, sender);
    }
}
