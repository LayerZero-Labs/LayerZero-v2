// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test, console } from "forge-std/Test.sol";

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { MessagingParams, MessagingReceipt, MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { ReadLibConfig } from "../../contracts/uln/readlib/ReadLibBase.sol";
import { ReadLib1002 } from "../../contracts/uln/readlib/ReadLib1002.sol";
import { ExecuteParam } from "../../contracts/uln/dvn/DVN.sol";

import { SetupRead } from "../util/SetupRead.sol";
import { PacketUtil } from "../util/Packet.sol";
import { Constant } from "../util/Constant.sol";
import { OptionsUtil } from "../util/OptionsUtil.sol";

contract ReadLib1002E2ETest is Test {
    using OptionsUtil for bytes;

    uint32 internal constant CONFIG_TYPE_CMD_LID_CONFIG = 1;

    SetupRead.FixtureRead internal fixture;
    ReadLib1002 internal readLib;
    EndpointV2 internal endpointV2;
    uint32 internal EID;
    uint32 internal CID = 666;

    uint256 internal constant ALICE_KEY = 0x0ac101;
    address internal ALICE;

    event PayloadSigned(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);
    event PacketSent(bytes encodedPayload, bytes options, address sendLibrary);
    event PacketVerified(Origin origin, address receiver, bytes32 payloadHash);

    function setUp() public {
        fixture = SetupRead.loadFixture(Constant.EID_ETHEREUM);
        readLib = fixture.cmdLib;
        endpointV2 = fixture.endpointV2;
        EID = fixture.eid;
        ALICE = vm.addr(ALICE_KEY);
    }

    function test_Quote() public {
        SetupRead.wireFixtureV2WithChannel(fixture, CID);

        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);

        // mock dvn fee
        uint256 mockDVNFee = 1;
        uint256 mockOptionalDVNFee = 2;

        ReadLibConfig memory readLibConfig;
        address dvn1 = address(0xd1);
        address dvn2 = address(0xd2);
        readLibConfig = ReadLibConfig(address(fixture.executor), 1, 1, 1, new address[](1), new address[](1));
        readLibConfig.requiredDVNs[0] = dvn1; // dvn 1
        readLibConfig.optionalDVNs[0] = dvn2; // dvn 2
        SetConfigParam[] memory cfParams = new SetConfigParam[](1);
        cfParams[0] = SetConfigParam(CID, CONFIG_TYPE_CMD_LID_CONFIG, abi.encode(readLibConfig));

        vm.prank(address(endpointV2));
        readLib.setConfig(address(fixture.oapp), cfParams);

        vm.mockCall(
            address(dvn1),
            abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"),
            abi.encode(mockDVNFee)
        );
        vm.mockCall(
            address(dvn2),
            abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"),
            abi.encode(mockOptionalDVNFee)
        );

        // mock executor fee
        uint256 mockExecutorFee = 3;
        vm.mockCall(
            address(fixture.executor),
            abi.encodeWithSignature("getFee(address,bytes)"),
            abi.encode(mockExecutorFee)
        );

        // mock treasury fee
        uint256 mockTreasuryFee = 4;
        vm.mockCall(
            address(fixture.treasury),
            abi.encodeWithSelector(fixture.treasury.getFee.selector),
            abi.encode(mockTreasuryFee)
        );

        MessagingFee memory quoteFee = fixture.oapp.quote(CID, false, options);
        assertEq(quoteFee.nativeFee, 1 + 2 + 3 + 4);
        assertEq(quoteFee.lzTokenFee, 0);
    }

    function test_Send() public {
        // wire to itself
        SetupRead.wireFixtureV2WithChannel(fixture, CID);

        Packet memory packetSent = PacketUtil.newPacket(
            1,
            EID,
            address(fixture.oapp),
            CID,
            address(fixture.oapp),
            fixture.oapp.cmd()
        );
        bytes memory encodedPacket = PacketV1Codec.encode(packetSent);
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);

        MessagingFee memory quoteFee = fixture.oapp.quote(CID, false, options);
        require(quoteFee.nativeFee > 0, "quoteFee.nativeFee must be greater than 0");
        require(quoteFee.lzTokenFee == 0, "quoteFee.lzTokenFee must be 0");

        vm.expectEmit(true, true, true, true, address(endpointV2));
        emit PacketSent(encodedPacket, options, address(fixture.cmdLib));

        vm.deal(ALICE, quoteFee.nativeFee);
        vm.prank(ALICE);
        MessagingReceipt memory receipt = fixture.oapp.send{ value: quoteFee.nativeFee }(CID, false, options);
        assertEq(receipt.nonce, 1);
        assertEq(receipt.fee.nativeFee, quoteFee.nativeFee);
        assertEq(receipt.fee.lzTokenFee, quoteFee.lzTokenFee);
    }

    function test_Send_LzTokenFee() public {
        // wire to itself
        SetupRead.wireFixtureV2WithChannel(fixture, CID);

        Packet memory packetSent = PacketUtil.newPacket(
            1,
            EID,
            address(fixture.oapp),
            CID,
            address(fixture.oapp),
            fixture.oapp.cmd()
        );
        bytes memory encodedPacket = PacketV1Codec.encode(packetSent);
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);

        MessagingFee memory quoteFee = fixture.oapp.quote(CID, true, options);
        require(quoteFee.nativeFee > 0, "quoteFee.nativeFee must be greater than 0");
        require(quoteFee.lzTokenFee > 0, "LzTokenFee should be greater than 0");

        // pay lzTokenFee
        fixture.lzToken.transfer(address(endpointV2), quoteFee.lzTokenFee);

        vm.expectEmit(true, true, true, true, address(endpointV2));
        emit PacketSent(encodedPacket, options, address(fixture.cmdLib));

        vm.deal(ALICE, quoteFee.nativeFee);
        vm.prank(ALICE);
        MessagingReceipt memory receipt = fixture.oapp.send{ value: quoteFee.nativeFee }(CID, true, options);
        assertEq(receipt.nonce, 1);
        assertEq(receipt.fee.nativeFee, quoteFee.nativeFee);
        assertEq(receipt.fee.lzTokenFee, quoteFee.lzTokenFee);
    }

    function test_receive() public {
        // wire to itself
        SetupRead.wireFixtureV2WithChannel(fixture, CID);

        // send packet
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);
        MessagingFee memory quoteFee = fixture.oapp.quote(CID, false, options);
        fixture.oapp.send{ value: quoteFee.nativeFee }(CID, false, options);

        Packet memory packetSent = PacketUtil.newPacket(
            1,
            EID,
            address(fixture.oapp),
            CID,
            address(fixture.oapp),
            fixture.oapp.cmd()
        );
        // flip the packet eid
        uint32 srcEid = packetSent.srcEid;
        packetSent.srcEid = packetSent.dstEid;
        packetSent.dstEid = srcEid;
        // dvn verify
        bytes memory resolvedMessage = "resolved message";
        verifyAndCommit(packetSent, resolvedMessage, fixture);

        Origin memory origin = PacketUtil.getOrigin(packetSent);
        address receiver = address(uint160(uint256(packetSent.receiver)));
        bytes32 guid = packetSent.guid;
        endpointV2.lzReceive(origin, receiver, guid, resolvedMessage, "");

        assertEq(fixture.oapp.ack(), 1);
    }

    // -------------- helper functions --------------
    function verifyAndCommit(
        Packet memory _packet,
        bytes memory _resolvedMessage,
        SetupRead.FixtureRead memory _fixture
    ) internal {
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(_packet);
        bytes32 cmdHash = keccak256(_fixture.oapp.cmd());
        bytes32 payloadHash = keccak256(abi.encodePacked(_packet.guid, _resolvedMessage));
        bytes memory verifyCallData = abi.encodeWithSelector(
            ReadLib1002.verify.selector,
            packetHeader,
            cmdHash,
            payloadHash
        );
        vm.prank(address(_fixture.dvn));
        _fixture.dvn.setSigner(ALICE, true);
        bytes32 callDataHash = _fixture.dvn.hashCallData(
            _fixture.eid % 30000,
            address(readLib),
            verifyCallData,
            block.timestamp + 500
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", callDataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        ExecuteParam[] memory executeParams = new ExecuteParam[](1);
        executeParams[0] = ExecuteParam(
            _fixture.eid % 30000,
            address(readLib),
            verifyCallData,
            block.timestamp + 500,
            signature
        );
        _fixture.dvn.execute(executeParams);

        // commit verification
        _fixture.cmdLib.commitVerification(packetHeader, cmdHash, payloadHash);
    }
}
