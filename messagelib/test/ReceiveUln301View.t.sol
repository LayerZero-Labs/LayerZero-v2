// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { IMessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { EndpointV1 } from "./mocks/EndpointV1.sol";

import { ReceiveUln301 } from "../contracts/uln/uln301/ReceiveUln301.sol";
import { ReceiveUln301View, VerificationState } from "../contracts/uln/uln301/ReceiveUln301View.sol";

import { Constant } from "./util/Constant.sol";
import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";

contract ReceiveUln301ViewTest is Test {
    Setup.FixtureV1 internal fixtureV1;
    ReceiveUln301 internal receiveUln301;
    ReceiveUln301View internal receiveUln301View;
    EndpointV1 internal endpointV1;
    uint16 internal EID;

    function setUp() public {
        vm.mockCall(address(0), abi.encodeWithSelector(IMessagingChannel.eid.selector), abi.encode(0));
        fixtureV1 = Setup.loadFixtureV1(Constant.EID_ETHEREUM);
        receiveUln301 = fixtureV1.receiveUln301;
        endpointV1 = fixtureV1.endpointV1;
        EID = fixtureV1.eid;
        receiveUln301View = new ReceiveUln301View();
        receiveUln301View.initialize(address(endpointV1), EID, address(receiveUln301));
    }

    function test_Verifiable_Verifying() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);

        Packet memory packet = PacketUtil.newPacket(
            1,
            EID,
            address(this),
            EID,
            address(this),
            abi.encodePacked("message")
        );
        bytes memory encodedPacket = PacketV1Codec.encode(packet);
        bytes memory header = BytesLib.slice(encodedPacket, 0, 81);
        bytes32 payloadHash = keccak256(BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81));
        VerificationState status = receiveUln301View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.Verifying));
    }

    function test_Verifiable_Verifiable() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);

        Packet memory packet = PacketUtil.newPacket(
            1,
            EID,
            address(this),
            EID,
            address(this),
            abi.encodePacked("message")
        );
        bytes memory encodedPacket = PacketV1Codec.encode(packet);

        bytes memory header = BytesLib.slice(encodedPacket, 0, 81);
        bytes memory payload = BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81);
        vm.prank(address(fixtureV1.dvn));
        receiveUln301.verify(header, keccak256(payload), 1);

        bytes32 payloadHash = keccak256(BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81));
        VerificationState status = receiveUln301View.verifiable(header, payloadHash);
        // in 301, verifiable will return as Verified, because it is ready to be executed
        assertEq(uint256(status), uint256(VerificationState.Verified));
    }

    function test_Verifiable_Verified() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);

        Packet memory packet = PacketUtil.newPacket(
            1,
            EID,
            address(this),
            EID,
            address(this),
            abi.encodePacked("message")
        );
        bytes memory encodedPacket = PacketV1Codec.encode(packet);

        bytes memory header = BytesLib.slice(encodedPacket, 0, 81);
        bytes memory payload = BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81);
        vm.prank(address(fixtureV1.dvn));
        receiveUln301.verify(header, keccak256(payload), 1);

        // verify
        vm.prank(address(fixtureV1.executor));
        receiveUln301.commitVerification(encodedPacket, 10000000);

        bytes32 payloadHash = keccak256(BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81));
        VerificationState status = receiveUln301View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.Verified));
    }
}
