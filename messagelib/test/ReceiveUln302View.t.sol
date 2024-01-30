// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { EndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { ReceiveUln302 } from "../contracts/uln/uln302/ReceiveUln302.sol";
import { ReceiveUln302View, VerificationState } from "../contracts/uln/uln302/ReceiveUln302View.sol";

import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { Constant } from "./util/Constant.sol";

contract ReceiveUln302ViewTest is Test {
    using AddressCast for address;

    Setup.FixtureV2 internal fixtureV2;
    ReceiveUln302 internal receiveUln302;
    ReceiveUln302View internal receiveUln302View;
    EndpointV2 internal endpointV2;
    uint32 internal EID;

    bool internal initializable = true;

    function setUp() public {
        fixtureV2 = Setup.loadFixtureV2(Constant.EID_ETHEREUM);
        receiveUln302 = fixtureV2.receiveUln302;
        endpointV2 = fixtureV2.endpointV2;
        EID = fixtureV2.eid;
        receiveUln302View = new ReceiveUln302View();
        receiveUln302View.initialize(address(endpointV2), address(receiveUln302));
    }

    function test_Verifiable_Verifying() public {
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
        VerificationState status = receiveUln302View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.Verifying));
    }

    function test_Verifiable_Verified() public {
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

        // verify
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(header, payloadHash, 1);

        // endpoint verifiable
        Origin memory origin = Origin(EID, address(this).toBytes32(), 1);
        assertTrue(receiveUln302View.verifiable(origin, address(this), address(receiveUln302), payloadHash));
        assertEq(endpointV2.inboundPayloadHash(address(this), EID, address(this).toBytes32(), 1), bytes32(0));

        // commitVerification
        receiveUln302.commitVerification(header, payloadHash);

        // endpoint allow reverifying
        assertTrue(receiveUln302View.verifiable(origin, address(this), address(receiveUln302), payloadHash));
        assertEq(endpointV2.inboundPayloadHash(address(this), EID, address(this).toBytes32(), 1), payloadHash);

        VerificationState status = receiveUln302View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.Verified));
    }

    function test_Verifiable_Verifiable() public {
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

        // dvn sign
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(header, payloadHash, 1);

        VerificationState status = receiveUln302View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.Verifiable));
    }

    function test_Verifiable_NotInitializable() public {
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

        // dvn sign
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(header, payloadHash, 1);

        // set app to not initializable
        initializable = false;

        VerificationState status = receiveUln302View.verifiable(header, payloadHash);
        assertEq(uint256(status), uint256(VerificationState.NotInitializable));
    }

    function allowInitializePath(Origin calldata) external view returns (bool) {
        return initializable;
    }
}
