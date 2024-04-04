// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PreCrimePeer} from "../../contracts/precrime/interfaces/IPreCrime.sol";
import {IOAppPreCrimeSimulator} from "../../contracts/precrime/interfaces/IOAppPreCrimeSimulator.sol";
import {PreCrimeUpgradeable} from "../../contracts/precrime/PreCrimeUpgradeable.sol";
import {InboundPacket} from "../../contracts/precrime/libs/Packet.sol";

import {PreCrimeV2SimulatorUpgradeableMock} from "./PreCrimeV2SimulatorUpgradeableMock.sol";

contract PreCrimeV2UpgradeableMock is PreCrimeUpgradeable {
    constructor(address _endpoint, address _simulator) PreCrimeUpgradeable(_endpoint, _simulator) {}

    uint32[] public eids;
    bytes[] public results;

    function initialize(address _delegate) external initializer {
        __Ownable_init();
        _transferOwnership(_delegate);
    }

    function buildSimulationResult() external view override returns (bytes memory) {
        return abi.encode(PreCrimeV2SimulatorUpgradeableMock(simulator).count());
    }

    function _getPreCrimePeers(InboundPacket[] memory _packets)
        internal
        view
        override
        returns (PreCrimePeer[] memory peers)
    {
        for (uint256 i = 0; i < _packets.length; i++) {
            InboundPacket memory packet = _packets[i];
            if (IOAppPreCrimeSimulator(simulator).isPeer(packet.origin.srcEid, packet.origin.sender)) {
                return preCrimePeers();
            }
        }
        return (new PreCrimePeer[](0));
    }

    function _preCrime(InboundPacket[] memory, uint32[] memory _eids, bytes[] memory _results) internal override {
        eids = _eids;
        results = _results;
    }
}
