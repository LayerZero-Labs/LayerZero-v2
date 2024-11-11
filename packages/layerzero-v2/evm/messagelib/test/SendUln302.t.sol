// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { MessagingParams, MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { UlnConfig } from "../contracts/uln/UlnBase.sol";
import { SendUln302 } from "../contracts/uln/uln302/SendUln302.sol";

import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { Constant } from "./util/Constant.sol";
import { OptionsUtil } from "./util/OptionsUtil.sol";

contract SendUln302Test is Test {
    using OptionsUtil for bytes;
    Setup.FixtureV2 internal fixtureV2;
    SendUln302 internal sendUln302;
    EndpointV2 internal endpointV2;
    uint32 internal EID;

    event PayloadSigned(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);
    event PacketVerified(Origin origin, address receiver, bytes32 payloadHash);

    function setUp() public {
        fixtureV2 = Setup.loadFixtureV2(Constant.EID_ETHEREUM);
        sendUln302 = fixtureV2.sendUln302;
        endpointV2 = fixtureV2.endpointV2;
        EID = fixtureV2.eid;
    }

    function test_Send() public {
        // wire to itself
        Setup.wireFixtureV2WithRemote(fixtureV2, EID);

        // bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter
        vm.expectEmit(false, false, false, false, address(endpointV2));
        emit PacketSent("payload", "options", address(0));
        bytes memory option = OptionsUtil.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingParams memory messagingParams = MessagingParams(EID, bytes32(uint256(1)), "message", option, false);
        endpointV2.send(messagingParams, payable(address(this)));
    }

    function test_Quote() public {
        // wire to itself
        Setup.wireFixtureV2WithRemote(fixtureV2, EID);

        vm.txGasPrice(10);
        // mock treasury fee
        uint256 mockTreasuryFee = 1;
        vm.mockCall(
            address(fixtureV2.treasury),
            abi.encodeWithSelector(fixtureV2.treasury.getFee.selector),
            abi.encode(mockTreasuryFee)
        );
        // mock executor fee
        uint256 mockExecutorFee = 2;
        vm.mockCall(
            address(fixtureV2.executor),
            abi.encodeWithSignature("getFee(uint32,address,uint256,bytes)"),
            abi.encode(mockExecutorFee)
        );

        // mock dvns fee
        uint256 mockDVNFee = 3;
        uint256 mockOptionalDVNFee = 4;

        UlnConfig memory ulnConfig;
        ulnConfig = UlnConfig(1, 1, 1, 1, new address[](1), new address[](1));
        ulnConfig.requiredDVNs[0] = address(0x1);
        ulnConfig.optionalDVNs[0] = address(0x2);

        SetConfigParam[] memory cfParams = new SetConfigParam[](1);
        cfParams[0] = SetConfigParam(EID, Constant.CONFIG_TYPE_ULN, abi.encode(ulnConfig));

        vm.prank(address(endpointV2));
        sendUln302.setConfig(address(this), cfParams);

        vm.mockCall(
            address(0x1),
            abi.encodeWithSignature("getFee(uint32,uint64,address,bytes)"),
            abi.encode(mockDVNFee)
        );
        vm.mockCall(
            address(0x2),
            abi.encodeWithSignature("getFee(uint32,uint64,address,bytes)"),
            abi.encode(mockOptionalDVNFee)
        );

        Packet memory p = PacketUtil.newPacket(1, EID, address(this), EID, address(this), "");
        MessagingFee memory msgFee = sendUln302.quote(
            p,
            OptionsUtil.newOptions().addExecutorLzReceiveOption(200000, 0),
            false
        );
        assertEq(msgFee.nativeFee, mockTreasuryFee + mockExecutorFee + mockDVNFee + mockOptionalDVNFee);
    }

    function test_Version() public {
        (uint64 major, uint64 minor, uint64 endpointVersion) = sendUln302.version();
        assertEq(major, 3);
        assertEq(minor, 0);
        assertEq(endpointVersion, 2);
    }
}
