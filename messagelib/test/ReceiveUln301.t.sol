// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { IMessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { EndpointV1 } from "./mocks/EndpointV1.sol";

import { Verification } from "../contracts/uln/ReceiveUlnBase.sol";
import { ReceiveUln301 } from "../contracts/uln/uln301/ReceiveUln301.sol";

import { Constant } from "./util/Constant.sol";
import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { OptionsUtil } from "./util/OptionsUtil.sol";

contract ReceiveUln301Test is Test {
    using OptionsUtil for bytes;
    Setup.FixtureV1 internal fixtureV1;
    ReceiveUln301 internal receiveUln301;
    EndpointV1 internal endpointV1;
    uint16 internal EID;

    // ULN301 sent event
    event PacketSent(bytes encodedPayload, bytes options, uint256 nativeFee, uint256 lzTokenFee);
    event PayloadVerified(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);
    event PacketDelivered(Origin origin, address receiver);
    event NativeFeeWithdrawn(address user, address receiver, uint256 amount);
    event PayloadStored(
        uint16 srcChainId,
        bytes srcAddress,
        address dstAddress,
        uint64 nonce,
        bytes payload,
        bytes reason
    );

    function setUp() public {
        vm.mockCall(address(0), abi.encodeWithSelector(IMessagingChannel.eid.selector), abi.encode(0));
        fixtureV1 = Setup.loadFixtureV1(Constant.EID_ETHEREUM);
        receiveUln301 = fixtureV1.receiveUln301;
        endpointV1 = fixtureV1.endpointV1;
        EID = fixtureV1.eid;
    }

    function test_verify() public {
        bytes32 payloadHash = keccak256("payload");
        vm.expectEmit(false, false, false, false, address(receiveUln301));
        emit PayloadVerified(address(this), "packetHeader", 1, payloadHash);
        receiveUln301.verify("packetHeader", payloadHash, 1);
        (bool submitted, uint64 confirmations_) = receiveUln301.hashLookup(
            keccak256("packetHeader"),
            payloadHash,
            address(this)
        );
        assertTrue(submitted);
        assertEq(confirmations_, 1);
    }

    function test_CommitVerification() public {
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

        // commit verification
        vm.prank(address(fixtureV1.executor));
        Origin memory origin = Origin(0, bytes32(0), 0);
        vm.expectEmit(false, false, false, false, address(receiveUln301));
        emit PacketDelivered(origin, address(0));
        receiveUln301.commitVerification(encodedPacket, 10000000);
    }

    function test_Version() public {
        (uint64 major, uint64 minor, uint64 endpointVersion) = receiveUln301.version();
        assertEq(major, 3);
        assertEq(minor, 0);
        assertEq(endpointVersion, 1);
    }
}
