// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { EndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { ReceiveUln302 } from "../contracts/uln/uln302/ReceiveUln302.sol";
import { ReceiveUlnBase, Verification } from "../contracts/uln/ReceiveUlnBase.sol";

import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { Constant } from "./util/Constant.sol";
import { OptionsUtil } from "./util/OptionsUtil.sol";

contract ReceiveUln302Test is Test {
    using OptionsUtil for bytes;
    Setup.FixtureV2 internal fixtureV2;
    ReceiveUln302 internal receiveUln302;
    EndpointV2 internal endpointV2;
    uint32 internal EID;

    event PayloadVerified(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);
    event PacketVerified(Origin origin, address receiver, bytes32 payloadHash);

    function setUp() public {
        fixtureV2 = Setup.loadFixtureV2(Constant.EID_ETHEREUM);
        receiveUln302 = fixtureV2.receiveUln302;
        endpointV2 = fixtureV2.endpointV2;
        EID = fixtureV2.eid;
    }

    function test_CommitVerification_Again() public {
        // wire to itself
        Setup.wireFixtureV2WithRemote(fixtureV2, EID);

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

        // dvn verify
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(header, payloadHash, 1);

        // commit verification
        receiveUln302.commitVerification(header, payloadHash);

        // dvn sign again
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(header, payloadHash, 1);

        // commit verification again
        vm.expectEmit(false, false, false, false, address(endpointV2));
        emit PacketVerified(Origin(0, bytes32(0), 0), address(0), bytes32(0));
        receiveUln302.commitVerification(header, payloadHash);
    }

    function test_CommitVerification() public {
        // wire to itself
        Setup.wireFixtureV2WithRemote(fixtureV2, EID);

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
        vm.prank(address(fixtureV2.dvn));
        // dvn sign
        receiveUln302.verify(header, keccak256(payload), 1);

        // commit verification
        vm.expectEmit(false, false, false, false, address(endpointV2));
        emit PacketVerified(Origin(0, bytes32(0), 0), address(0), bytes32(0));
        receiveUln302.commitVerification(header, keccak256(payload));
    }

    function test_verify() public {
        bytes32 payloadHash = keccak256("payload");
        vm.expectEmit(false, false, false, false, address(receiveUln302));
        emit PayloadVerified(address(this), "packetHeader", 1, payloadHash);
        receiveUln302.verify("packetHeader", payloadHash, 1);
        (bool submitted, uint64 confirmations_) = receiveUln302.hashLookup(
            keccak256("packetHeader"),
            payloadHash,
            address(this)
        );
        assertTrue(submitted);
        assertEq(confirmations_, 1);
    }

    function test_Version() public {
        (uint64 major, uint64 minor, uint64 endpointVersion) = receiveUln302.version();
        assertEq(major, 3);
        assertEq(minor, 0);
        assertEq(endpointVersion, 2);
    }

    function allowInitializePath(Origin calldata) external pure returns (bool) {
        return true;
    }
}
