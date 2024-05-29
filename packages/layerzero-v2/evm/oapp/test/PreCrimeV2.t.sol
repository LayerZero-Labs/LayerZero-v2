// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { IPreCrime, PreCrimePeer } from "../contracts/precrime/interfaces/IPreCrime.sol";
import { InboundPacket } from "../contracts/precrime/libs/Packet.sol";

import { TestHelper } from "./TestHelper.sol";
import { PreCrimeV2Mock } from "./mocks/PreCrimeV2Mock.sol";
import { PreCrimeV2SimulatorMock } from "./mocks/PreCrimeV2SimulatorMock.sol";

import "forge-std/console.sol";

contract PreCrimeV2Test is TestHelper {
    uint16 constant CONFIG_VERSION = 2;
    uint64 constant MAX_BATCH_SIZE = 4;
    address constant OFF_CHAIN = address(0xDEAD);

    PreCrimeV2Mock preCrime;
    PreCrimeV2SimulatorMock simulator;

    PreCrimePeer[] preCrimePeers;

    function setUp() public override {
        super.setUp();

        setUpEndpoints(1, LibraryType.SimpleMessageLib);

        simulator = new PreCrimeV2SimulatorMock();
        preCrime = new PreCrimeV2Mock(address(endpoints[1]), address(simulator));

        preCrimePeers.push(PreCrimePeer(2, bytes32(uint256(22)), bytes32(uint256(2))));
        preCrimePeers.push(PreCrimePeer(3, bytes32(uint256(33)), bytes32(uint256(3))));

        preCrime.setPreCrimePeers(preCrimePeers);
        preCrime.setMaxBatchSize(MAX_BATCH_SIZE);
    }

    function test_getConfig() public {
        uint256[] memory packetMsgValues = new uint256[](1);

        // return config with all peers if no packet
        vm.startPrank(OFF_CHAIN);
        bytes memory config = preCrime.getConfig(new bytes[](0), packetMsgValues);
        bytes memory expectedConfig = abi.encodePacked(CONFIG_VERSION, MAX_BATCH_SIZE, _encodePeers(preCrimePeers));
        assertEq(config, expectedConfig);

        // return config without peers if packet from untrusted peer
        bytes[] memory packets = _buildPacket(2, bytes32(0), 1, 1); // untrusted peer
        config = preCrime.getConfig(packets, packetMsgValues);
        expectedConfig = abi.encodePacked(CONFIG_VERSION, MAX_BATCH_SIZE);
        assertEq(config, expectedConfig);

        // return config with peers if packet from trusted peer
        packets = _buildPacket(2, bytes32(uint256(2)), 1, 1); // trusted peer
        config = preCrime.getConfig(packets, packetMsgValues);
        expectedConfig = abi.encodePacked(CONFIG_VERSION, MAX_BATCH_SIZE, _encodePeers(preCrimePeers));
        assertEq(config, expectedConfig);
    }

    function test_simulate_packetOverSize() public {
        uint256[] memory packetMsgValues = new uint256[](5);
        bytes[] memory packets = _buildPacket(2, bytes32(uint256(2)), 1, 5); // too many packets
        vm.startPrank(OFF_CHAIN);
        bytes memory expectedError = abi.encodeWithSelector(IPreCrime.PacketOversize.selector, 4, 5);
        vm.expectRevert(expectedError);
        preCrime.simulate(packets, packetMsgValues);
    }

    function test_simulate_packetUnsorted() public {
        uint256[] memory packetMsgValues = new uint256[](4);
        bytes[] memory unsortedPackets = new bytes[](4);
        unsortedPackets[0] = _buildPacket(2, bytes32(uint256(2)), 1, 1)[0];
        unsortedPackets[1] = _buildPacket(3, bytes32(uint256(3)), 1, 1)[0]; // unsorted
        unsortedPackets[2] = _buildPacket(2, bytes32(uint256(2)), 2, 1)[0];
        unsortedPackets[3] = _buildPacket(3, bytes32(uint256(4)), 1, 1)[0]; // untrested peer, but skipped

        vm.startPrank(OFF_CHAIN);
        bytes memory expectedError = abi.encodeWithSelector(IPreCrime.PacketUnsorted.selector);
        vm.expectRevert(expectedError);
        preCrime.simulate(unsortedPackets, packetMsgValues);
    }

    function test_simulate_failed() public {
        // empty packetMsgValues to be reused
        uint256[] memory packetMsgValues = new uint256[](1);
        bytes[] memory packets = _buildPacket(0, bytes32(0), 1, 1); // invalid packet and simulation failed
        vm.startPrank(OFF_CHAIN);
        bytes memory expectedError = abi.encodeWithSelector(
            IPreCrime.SimulationFailed.selector,
            abi.encodeWithSelector(PreCrimeV2SimulatorMock.InvalidEid.selector)
        );
        vm.expectRevert(expectedError);
        preCrime.simulate(packets, packetMsgValues);
    }

    function test_simulate() public {
        uint256[] memory packetMsgValues = new uint256[](4);
        bytes[] memory packets = _buildPacket(2, bytes32(uint256(2)), 1, 2);
        packets = _appendPackets(packets, _buildPacket(3, bytes32(uint256(3)), 1, 2));

        vm.startPrank(OFF_CHAIN);
        bytes memory result = preCrime.simulate(packets, packetMsgValues);
        bytes memory expectedResult = abi.encodePacked(uint32(1), uint256(4)); // receive 4 packets
        assertEq(result, expectedResult);
    }

    function test_preCrime_simulationResultNotFound() public {
        uint256[] memory packetMsgValues = new uint256[](1);
        bytes[] memory packets = _buildPacket(2, bytes32(uint256(2)), 1, 1);

        // result of eid 3 not found
        bytes[] memory results = new bytes[](2);
        results[0] = abi.encodePacked(uint32(1), uint256(1));
        results[1] = abi.encodePacked(uint32(2), uint256(1));

        vm.startPrank(OFF_CHAIN);
        bytes memory expectedError = abi.encodeWithSelector(IPreCrime.SimulationResultNotFound.selector, 3);
        vm.expectRevert(expectedError);
        preCrime.preCrime(packets, packetMsgValues, results);

        // result of eid 1 (local result) not found
        results[0] = abi.encodePacked(uint32(2), uint256(1));
        results[1] = abi.encodePacked(uint32(3), uint256(1));

        expectedError = abi.encodeWithSelector(IPreCrime.SimulationResultNotFound.selector, 1);
        vm.expectRevert(expectedError);
        preCrime.preCrime(packets, packetMsgValues, results);
    }

    function test_preCrime() public {
        uint256[] memory packetMsgValues = new uint256[](1);
        bytes[] memory packets = _buildPacket(2, bytes32(uint256(2)), 1, 1);

        bytes[] memory results = new bytes[](3);
        results[0] = abi.encodePacked(uint32(1), uint256(1));
        results[1] = abi.encodePacked(uint32(2), uint256(2));
        results[2] = abi.encodePacked(uint32(3), uint256(3));

        vm.startPrank(OFF_CHAIN);
        preCrime.preCrime(packets, packetMsgValues, results);

        // check internal state of preCrime
        assertEq(preCrime.eids(0), 1);
        assertEq(preCrime.eids(1), 2);
        assertEq(preCrime.eids(2), 3);
        assertEq(preCrime.results(0), abi.encode(1));
        assertEq(preCrime.results(1), abi.encode(2));
        assertEq(preCrime.results(2), abi.encode(3));
    }

    function _buildPacket(
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        uint256 _packetNum
    ) internal view returns (bytes[] memory) {
        bytes[] memory packets = new bytes[](_packetNum);
        for (uint256 i = 0; i < _packetNum; ++i) {
            InboundPacket memory packet = InboundPacket(
                Origin(_srcEid, _sender, _nonce + uint64(i)),
                1,
                preCrime.oApp(),
                bytes32(0),
                0,
                address(0),
                "",
                ""
            );
            packets[i] = _encodePacket(packet);
        }
        return packets;
    }

    function _encodePacket(InboundPacket memory _packet) internal pure returns (bytes memory encodedPacket) {
        encodedPacket = abi.encodePacked(
            uint8(1),
            _packet.origin.nonce,
            _packet.origin.srcEid,
            _packet.origin.sender,
            _packet.dstEid,
            bytes32(uint256(uint160(_packet.receiver))),
            _packet.guid,
            _packet.value,
            _packet.message
        );
    }

    function _appendPackets(
        bytes[] memory _packets,
        bytes[] memory _newPackets
    ) internal pure returns (bytes[] memory) {
        bytes[] memory packets = new bytes[](_packets.length + _newPackets.length);
        for (uint256 i = 0; i < _packets.length; ++i) {
            packets[i] = _packets[i];
        }
        for (uint256 i = 0; i < _newPackets.length; ++i) {
            packets[_packets.length + i] = _newPackets[i];
        }
        return packets;
    }

    function _encodePeers(PreCrimePeer[] memory _peers) internal pure returns (bytes memory) {
        bytes memory peers = abi.encodePacked(uint16(_peers.length));
        for (uint256 i = 0; i < _peers.length; ++i) {
            peers = abi.encodePacked(peers, _peers[i].eid, _peers[i].preCrime, _peers[i].oApp);
        }
        return peers;
    }
}
