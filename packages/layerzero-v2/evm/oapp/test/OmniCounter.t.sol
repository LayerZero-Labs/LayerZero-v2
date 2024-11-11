// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { Errors } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Errors.sol";

import { OptionsBuilder } from "../contracts/oapp/libs/OptionsBuilder.sol";
import { OmniCounter, MsgCodec } from "../contracts/oapp/examples/OmniCounter.sol";
import { OmniCounterPreCrime } from "../contracts/oapp/examples/OmniCounterPreCrime.sol";
import { PreCrimePeer } from "../contracts/precrime/interfaces/IPreCrime.sol";

import { TestHelper } from "./TestHelper.sol";

import "forge-std/console.sol";

contract OmniCounterTest is TestHelper {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;

    // omnicounter with precrime
    OmniCounter aCounter;
    OmniCounterPreCrime aPreCrime;
    OmniCounter bCounter;
    OmniCounterPreCrime bPreCrime;

    address offchain = address(0xDEAD);

    error CrimeFound(bytes crime);

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        address[] memory uas = setupOApps(type(OmniCounter).creationCode, 1, 2);
        aCounter = OmniCounter(payable(uas[0]));
        bCounter = OmniCounter(payable(uas[1]));

        setUpPreCrime();
    }

    function setUpPreCrime() public {
        // set up precrime for aCounter
        aPreCrime = new OmniCounterPreCrime(address(aCounter.endpoint()), address(aCounter));
        aPreCrime.setMaxBatchSize(10);

        PreCrimePeer[] memory aCounterPreCrimePeers = new PreCrimePeer[](1);
        aCounterPreCrimePeers[0] = PreCrimePeer(
            bEid,
            addressToBytes32(address(bPreCrime)),
            addressToBytes32(address(bCounter))
        );
        aPreCrime.setPreCrimePeers(aCounterPreCrimePeers);

        aCounter.setPreCrime(address(aPreCrime));

        // set up precrime for bCounter
        bPreCrime = new OmniCounterPreCrime(address(bCounter.endpoint()), address(bCounter));
        bPreCrime.setMaxBatchSize(10);

        PreCrimePeer[] memory bCounterPreCrimePeers = new PreCrimePeer[](1);
        bCounterPreCrimePeers[0] = PreCrimePeer(
            aEid,
            addressToBytes32(address(aPreCrime)),
            addressToBytes32(address(aCounter))
        );
        bPreCrime.setPreCrimePeers(bCounterPreCrimePeers);

        bCounter.setPreCrime(address(bPreCrime));
    }

    // classic message passing A -> B
    function test_increment(uint8 numIncrements) public {
        vm.assume(numIncrements > 0 && numIncrements < 10); // upper bound to ensure tests don't run too long
        uint256 counterBefore = bCounter.count();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.VANILLA_TYPE, options);
        for (uint8 i = 0; i < numIncrements; i++) {
            aCounter.increment{ value: nativeFee }(bEid, MsgCodec.VANILLA_TYPE, options);
        }
        assertEq(bCounter.count(), counterBefore, "shouldn't be increased until packet is verified");

        // verify packet to bCounter manually
        verifyPackets(bEid, addressToBytes32(address(bCounter)));

        assertEq(bCounter.count(), counterBefore + numIncrements, "increment assertion failure");
    }

    function test_batchIncrement(uint256 batchSize) public {
        vm.assume(batchSize > 0 && batchSize < 10);

        uint256 counterBefore = bCounter.count();

        uint32[] memory eids = new uint32[](batchSize);
        uint8[] memory types = new uint8[](batchSize);
        bytes[] memory options = new bytes[](batchSize);
        bytes memory option = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint256 fee;
        for (uint256 i = 0; i < batchSize; i++) {
            eids[i] = bEid;
            types[i] = MsgCodec.VANILLA_TYPE;
            options[i] = option;
            (uint256 nativeFee, ) = aCounter.quote(eids[i], types[i], options[i]);
            fee += nativeFee;
        }

        vm.expectRevert(); // Errors.InvalidAmount
        aCounter.batchIncrement{ value: fee - 1 }(eids, types, options);

        aCounter.batchIncrement{ value: fee }(eids, types, options);
        verifyPackets(bEid, addressToBytes32(address(bCounter)));

        assertEq(bCounter.count(), counterBefore + batchSize, "batchIncrement assertion failure");
    }

    function test_nativeDrop_increment(uint128 nativeDropGas) public {
        vm.assume(nativeDropGas <= 100000000000000000); // avoid encountering Executor_NativeAmountExceedsCap
        uint256 balanceBefore = address(bCounter).balance;

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorNativeDropOption(nativeDropGas, addressToBytes32(address(bCounter)));
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.VANILLA_TYPE, options);
        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.VANILLA_TYPE, options);

        // verify packet to bCounter manually
        verifyPackets(bEid, addressToBytes32(address(bCounter)));

        assertEq(address(bCounter).balance, balanceBefore + nativeDropGas, "nativeDrop assertion failure");

        // transfer funds out
        address payable receiver = payable(address(0xABCD));

        // withdraw with non admin
        vm.startPrank(receiver);
        vm.expectRevert();
        bCounter.withdraw(receiver, nativeDropGas);
        vm.stopPrank();

        // withdraw with admin
        bCounter.withdraw(receiver, nativeDropGas);
        assertEq(address(bCounter).balance, 0, "withdraw assertion failure");
        assertEq(receiver.balance, nativeDropGas, "withdraw assertion failure");
    }

    // classic message passing A -> B1 -> B2
    function test_lzCompose_increment() public {
        uint256 countBefore = bCounter.count();
        uint256 composedCountBefore = bCounter.composedCount();

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 200000, 0);
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.COMPOSED_TYPE, options);
        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.COMPOSED_TYPE, options);

        verifyPackets(bEid, addressToBytes32(address(bCounter)), 0, address(bCounter));

        assertEq(bCounter.count(), countBefore + 1, "increment B1 assertion failure");
        assertEq(bCounter.composedCount(), composedCountBefore + 1, "increment B2 assertion failure");
    }

    // A -> B -> A
    function test_ABA_increment() public {
        uint256 countABefore = aCounter.count();
        uint256 countBBefore = bCounter.count();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(10000000, 10000000);
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.ABA_TYPE, options);
        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.ABA_TYPE, options);

        verifyPackets(bEid, addressToBytes32(address(bCounter)));
        assertEq(aCounter.count(), countABefore, "increment A assertion failure");
        assertEq(bCounter.count(), countBBefore + 1, "increment B assertion failure");

        verifyPackets(aEid, addressToBytes32(address(aCounter)));
        assertEq(aCounter.count(), countABefore + 1, "increment A assertion failure");
    }

    // A -> B1 -> B2 -> A
    function test_lzCompose_ABA_increment() public {
        uint256 countABefore = aCounter.count();
        uint256 countBBefore = bCounter.count();
        uint256 composedCountBBefore = bCounter.composedCount();

        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 10000000, 10000000);
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.COMPOSED_ABA_TYPE, options);
        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.COMPOSED_ABA_TYPE, options);

        verifyPackets(bEid, addressToBytes32(address(bCounter)), 0, address(bCounter));
        assertEq(bCounter.count(), countBBefore + 1, "increment B1 assertion failure");
        assertEq(bCounter.composedCount(), composedCountBBefore + 1, "increment B2 assertion failure");

        verifyPackets(aEid, addressToBytes32(address(aCounter)));
        assertEq(aCounter.count(), countABefore + 1, "increment A assertion failure");
    }

    function test_omniCounterPreCrime() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 nativeFee, ) = aCounter.quote(bEid, MsgCodec.VANILLA_TYPE, options);

        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.VANILLA_TYPE, options);
        aCounter.increment{ value: nativeFee }(bEid, MsgCodec.VANILLA_TYPE, options);
        assertEq(aCounter.outboundCount(bEid), 2, "outboundCount assertion failure");

        // precrime should pass
        bytes[] memory packets = new bytes[](2);
        uint256[] memory packetMsgValues = new uint256[](2);
        bytes memory message = MsgCodec.encode(MsgCodec.VANILLA_TYPE, aEid);
        packets[0] = PacketV1Codec.encode(
            Packet(1, aEid, address(aCounter), bEid, addressToBytes32(address(bCounter)), bytes32(0), message)
        );
        packets[1] = PacketV1Codec.encode(
            Packet(2, aEid, address(aCounter), bEid, addressToBytes32(address(bCounter)), bytes32(0), message)
        );

        vm.startPrank(offchain);

        bytes[] memory simulations = new bytes[](2);
        simulations[0] = aPreCrime.simulate(new bytes[](0), new uint256[](0));
        simulations[1] = bPreCrime.simulate(packets, packetMsgValues);

        bPreCrime.preCrime(packets, packetMsgValues, simulations);

        verifyPackets(bEid, addressToBytes32(address(bCounter)));
        assertEq(bCounter.inboundCount(aEid), 2, "inboundCount assertion failure");

        vm.startPrank(address(this));

        // precrime a broken increment
        aCounter.brokenIncrement{ value: nativeFee }(bEid, MsgCodec.VANILLA_TYPE, options);
        assertEq(aCounter.outboundCount(bEid), 2, "outboundCount assertion failure"); // broken outbound increment

        packets = new bytes[](1);
        packetMsgValues = new uint256[](1);
        packets[0] = PacketV1Codec.encode(
            Packet(3, aEid, address(aCounter), bEid, addressToBytes32(address(bCounter)), bytes32(0), message)
        );

        vm.startPrank(offchain);

        simulations[0] = aPreCrime.simulate(new bytes[](0), new uint256[](0));
        simulations[1] = bPreCrime.simulate(packets, packetMsgValues);

        bytes memory expectedError = abi.encodeWithSelector(CrimeFound.selector, "inboundCount > outboundCount");
        vm.expectRevert(expectedError);

        bPreCrime.preCrime(packets, packetMsgValues, simulations);

        verifyPackets(bEid, addressToBytes32(address(bCounter)));
        assertEq(bCounter.inboundCount(aEid), 3, "inboundCount assertion failure"); // state broken
    }
}
