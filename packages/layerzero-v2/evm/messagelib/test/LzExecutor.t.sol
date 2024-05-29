// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { ILayerZeroReceiver } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { ExecutionState } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2View.sol";

import { ReceiveUln302 } from "../contracts/uln/uln302/ReceiveUln302.sol";
import { LzExecutor, LzReceiveParam, NativeDropParam } from "../contracts/uln/LzExecutor.sol";
import { VerificationState, ReceiveUln302View } from "../contracts/uln/uln302/ReceiveUln302View.sol";

import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { Constant } from "./util/Constant.sol";

contract LzExecutorTest is Test, ILayerZeroReceiver {
    Setup.FixtureV2 internal fixtureV2;
    ReceiveUln302 internal receiveUln302;
    ReceiveUln302View internal receiveUln302View;
    ILayerZeroEndpointV2 internal endpointV2;
    LzExecutor internal lzExecutor;
    uint32 internal EID;

    Origin origin;
    Packet packet;
    bytes packetHeader;
    bytes32 payloadHash;
    address receiver;

    address alice = address(0x1234);

    function setUp() public {
        fixtureV2 = Setup.loadFixtureV2(Constant.EID_ETHEREUM);
        endpointV2 = ILayerZeroEndpointV2(fixtureV2.endpointV2);
        receiveUln302 = fixtureV2.receiveUln302;
        receiveUln302View = new ReceiveUln302View();
        receiveUln302View.initialize(address(fixtureV2.endpointV2), address(receiveUln302));
        lzExecutor = new LzExecutor();
        lzExecutor.initialize(
            address(fixtureV2.receiveUln302),
            address(receiveUln302View),
            address(fixtureV2.endpointV2)
        );
        EID = fixtureV2.eid;

        // wire to self
        Setup.wireFixtureV2WithRemote(fixtureV2, fixtureV2.eid);

        // setup packet
        origin = Origin(EID, bytes32(uint256(uint160(address(this)))), 1);
        receiver = address(this);
        packet = PacketUtil.newPacket(1, EID, address(this), EID, receiver, abi.encodePacked("message"));
        origin = Origin(packet.srcEid, bytes32(uint256(uint160(packet.sender))), packet.nonce);
        bytes memory encodedPacket = PacketV1Codec.encode(packet);
        packetHeader = BytesLib.slice(encodedPacket, 0, 81);
        payloadHash = keccak256(BytesLib.slice(encodedPacket, 81, encodedPacket.length - 81));

        origin = Origin(EID, bytes32(uint256(uint160(address(this)))), 1);
        receiver = address(this);
    }

    function test_CommitAndExecute_OnlyExecute() public {
        // verify
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(packetHeader, payloadHash, 1);
        receiveUln302.commitVerification(packetHeader, payloadHash);

        // verified
        assertEq(uint256(receiveUln302View.verifiable(packetHeader, payloadHash)), uint256(VerificationState.Verified));
        // executable
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.Executable));

        // commit and execute
        NativeDropParam[] memory nativeDrop = new NativeDropParam[](0);
        lzExecutor.commitAndExecute(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );

        // executed
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.Executed));
    }

    function test_CommitAndExecute_NativeDropAndExecute() public {
        // verify
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(packetHeader, payloadHash, 1);
        receiveUln302.commitVerification(packetHeader, payloadHash);

        vm.deal(address(this), 1000);
        assertEq(alice.balance, 0); // alice had no funds
        // commit and execute
        NativeDropParam[] memory nativeDrop = new NativeDropParam[](1);
        nativeDrop[0] = NativeDropParam(alice, 1000);
        lzExecutor.commitAndExecute{ value: 1000 }(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );
        assertEq(address(this).balance, 0);
        assertEq(address(lzExecutor).balance, 0);
        assertEq(alice.balance, 1000); // alice received funds

        // executed
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.Executed));
    }

    function test_CommitAndExecute_ExecuteWithValue() public {
        // verify
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(packetHeader, payloadHash, 1);
        receiveUln302.commitVerification(packetHeader, payloadHash);

        vm.deal(address(this), 1000);
        // commit and execute
        NativeDropParam[] memory nativeDrop = new NativeDropParam[](0);
        lzExecutor.commitAndExecute{ value: 1000 }(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 1000),
            nativeDrop
        );
        assertEq(address(lzExecutor).balance, 0);
        assertEq(address(this).balance, 1000);

        // executed
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.Executed));
    }

    function test_CommitAndExecute_VerifyAndExecute() public {
        // verifiable
        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(packetHeader, payloadHash, 1);

        // verifiable
        assertEq(
            uint256(receiveUln302View.verifiable(packetHeader, payloadHash)),
            uint256(VerificationState.Verifiable)
        );
        // not executable
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.NotExecutable));

        // commit and execute
        NativeDropParam[] memory nativeDrop = new NativeDropParam[](0);
        lzExecutor.commitAndExecute(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );

        // verified
        assertEq(uint256(receiveUln302View.verifiable(packetHeader, payloadHash)), uint256(VerificationState.Verified));
        // executed
        assertEq(uint256(lzExecutor.executable(origin, receiver)), uint256(ExecutionState.Executed));
    }

    function test_CommitAndExecute_Revert_Verifying() public {
        assertEq(
            uint256(receiveUln302View.verifiable(packetHeader, payloadHash)),
            uint256(VerificationState.Verifying)
        );

        NativeDropParam[] memory nativeDrop = new NativeDropParam[](0);
        vm.expectRevert(LzExecutor.LzExecutor_Verifying.selector);
        lzExecutor.commitAndExecute(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );
    }

    function test_CommitAndExecute_Revert_Executed() public {
        NativeDropParam[] memory nativeDrop = new NativeDropParam[](0);

        vm.prank(address(fixtureV2.dvn));
        receiveUln302.verify(packetHeader, payloadHash, 1);
        lzExecutor.commitAndExecute(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );

        // try again
        vm.expectRevert(LzExecutor.LzExecutor_Executed.selector);
        lzExecutor.commitAndExecute(
            address(receiveUln302),
            LzReceiveParam(origin, receiver, packet.guid, packet.message, "", 100000, 0),
            nativeDrop
        );
    }

    function test_WithdrawNative() public {
        vm.deal(address(lzExecutor), 1000);
        assertEq(address(lzExecutor).balance, 1000);
        assertEq(alice.balance, 0);

        lzExecutor.withdrawNative(address(0x1234), 1000);
        assertEq(address(lzExecutor).balance, 0);
        assertEq(alice.balance, 1000);
    }

    function test_WithdrawNative_Revert_OnlyOwner() public {
        vm.deal(address(lzExecutor), 1000);
        assertEq(address(lzExecutor).balance, 1000);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        lzExecutor.withdrawNative(alice, 1000);
    }

    // implement ILayerZeroReceiver
    function allowInitializePath(Origin calldata) external pure override returns (bool) {
        return true;
    }

    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0;
    }

    function lzReceive(Origin calldata, bytes32, bytes calldata, address, bytes calldata) external payable override {
        // do nothing
    }
}
