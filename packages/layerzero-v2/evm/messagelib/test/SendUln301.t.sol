// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { IMessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { EndpointV1 } from "./mocks/EndpointV1.sol";

import { UlnConfig } from "../contracts/uln/UlnBase.sol";
import { SendUln301 } from "../contracts/uln/uln301/SendUln301.sol";

import { Constant } from "./util/Constant.sol";
import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { OptionsUtil } from "./util/OptionsUtil.sol";

contract SendUln301Test is Test {
    using OptionsUtil for bytes;
    Setup.FixtureV1 internal fixtureV1;
    SendUln301 internal sendUln301;
    EndpointV1 internal endpointV1;
    uint16 internal EID;

    // ULN301 sent event
    event PacketSent(bytes encodedPayload, bytes options, uint256 nativeFee, uint256 lzTokenFee);
    event PayloadSigned(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);
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
        sendUln301 = fixtureV1.sendUln301;
        endpointV1 = fixtureV1.endpointV1;
        EID = fixtureV1.eid;
    }

    function test_Send() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);

        // bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter
        vm.expectEmit(false, false, false, false, address(sendUln301));
        emit PacketSent("payload", "options", 0, 0);
        bytes memory option = OptionsUtil.newOptions().addExecutorLzReceiveOption(200000, 0);
        endpointV1.send(
            EID,
            abi.encodePacked(address(0x1), address(this)),
            "payload",
            payable(address(0x1)),
            address(0),
            option
        );
    }

    function test_EstimateFees() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);

        vm.txGasPrice(10);
        // mock treasury fee
        uint256 mockTreasuryFee = 1;
        vm.mockCall(
            address(fixtureV1.treasury),
            abi.encodeWithSelector(fixtureV1.treasury.getFee.selector),
            abi.encode(mockTreasuryFee)
        );
        // mock executor fee
        uint256 mockExecutorFee = 2;
        vm.mockCall(
            address(fixtureV1.executor),
            abi.encodeWithSelector(fixtureV1.executor.getFee.selector),
            abi.encode(mockExecutorFee)
        );

        // mock dvns fee
        uint256 mockDVNFee = 3;
        uint256 mockOptionalDVNFee = 4;

        UlnConfig memory ulnConfig;
        ulnConfig = UlnConfig(1, 1, 1, 1, new address[](1), new address[](1));
        ulnConfig.requiredDVNs[0] = address(0x1);
        ulnConfig.optionalDVNs[0] = address(0x2);

        vm.prank(address(endpointV1));
        sendUln301.setConfig(EID, address(this), Constant.CONFIG_TYPE_ULN, abi.encode(ulnConfig));

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

        // quote with nativeFee for treasury
        uint256 nativeFee;
        bytes memory option = OptionsUtil.newOptions().addExecutorLzReceiveOption(200000, 0);
        (nativeFee, ) = sendUln301.estimateFees(EID, address(this), "message", false, option);
        assertEq(nativeFee, mockTreasuryFee + mockExecutorFee + mockDVNFee + mockOptionalDVNFee);

        // quote with lzTokenFee for treasury
        uint256 lzTokenFee;
        (nativeFee, lzTokenFee) = sendUln301.estimateFees(EID, address(this), "message", true, option);
        assertEq(nativeFee, mockExecutorFee + mockDVNFee + mockOptionalDVNFee);
        assertEq(lzTokenFee, mockTreasuryFee);
    }

    function test_WithdrawFee() public {
        // wire to itself
        Setup.wireFixtureV1WithRemote(fixtureV1, EID);
        vm.txGasPrice(10);
        // mock treasury fee
        uint256 mockTreasuryFee = 1;
        vm.mockCall(
            address(fixtureV1.treasury),
            abi.encodeWithSelector(fixtureV1.treasury.payFee.selector),
            abi.encode(mockTreasuryFee)
        );
        bytes memory option = OptionsUtil.newOptions().addExecutorLzReceiveOption(200000, 0);
        endpointV1.send{ value: mockTreasuryFee }(
            EID,
            abi.encodePacked(address(0x1), address(this)),
            "payload",
            payable(address(0x1)),
            address(0),
            option
        );

        vm.expectEmit(false, false, false, true, address(sendUln301));
        emit NativeFeeWithdrawn(address(fixtureV1.treasury), address(0x1), mockTreasuryFee);
        vm.prank(address(fixtureV1.treasury));
        sendUln301.withdrawFee(address(0x1), mockTreasuryFee);
        assertEq(address(0x1).balance, mockTreasuryFee);
    }

    function test_Version() public {
        (uint64 major, uint64 minor, uint64 endpointVersion) = sendUln301.version();
        assertEq(major, 3);
        assertEq(minor, 0);
        assertEq(endpointVersion, 1);
    }
}
