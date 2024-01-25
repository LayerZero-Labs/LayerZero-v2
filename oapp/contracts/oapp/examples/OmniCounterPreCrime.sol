// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { PreCrime, PreCrimePeer } from "../../precrime/PreCrime.sol";
import { InboundPacket } from "../../precrime/libs/Packet.sol";
import { OmniCounter } from "./OmniCounter.sol";

contract OmniCounterPreCrime is PreCrime {
    struct ChainCount {
        uint32 remoteEid;
        uint256 inboundCount;
        uint256 outboundCount;
    }

    constructor(address _endpoint, address _counter, address _owner) PreCrime(_endpoint, _counter, _owner) {}

    function buildSimulationResult() external view override returns (bytes memory) {
        address payable payableSimulator = payable(simulator);
        OmniCounter counter = OmniCounter(payableSimulator);
        ChainCount[] memory chainCounts = new ChainCount[](preCrimePeers.length);
        for (uint256 i = 0; i < preCrimePeers.length; i++) {
            uint32 remoteEid = preCrimePeers[i].eid;
            chainCounts[i] = ChainCount(remoteEid, counter.inboundCount(remoteEid), counter.outboundCount(remoteEid));
        }
        return abi.encode(chainCounts);
    }

    function _preCrime(
        InboundPacket[] memory /** _packets */,
        uint32[] memory _eids,
        bytes[] memory _simulations
    ) internal view override {
        uint32 localEid = _getLocalEid();
        ChainCount[] memory localChainCounts;

        // find local chain counts
        for (uint256 i = 0; i < _eids.length; i++) {
            if (_eids[i] == localEid) {
                localChainCounts = abi.decode(_simulations[i], (ChainCount[]));
                break;
            }
        }

        // local against remote
        for (uint256 i = 0; i < _eids.length; i++) {
            uint32 remoteEid = _eids[i];
            ChainCount[] memory remoteChainCounts = abi.decode(_simulations[i], (ChainCount[]));
            (uint256 _inboundCount, ) = _findChainCounts(localChainCounts, remoteEid);
            (, uint256 _outboundCount) = _findChainCounts(remoteChainCounts, localEid);
            if (_inboundCount > _outboundCount) {
                revert CrimeFound("inboundCount > outboundCount");
            }
        }
    }

    function _findChainCounts(
        ChainCount[] memory _chainCounts,
        uint32 _remoteEid
    ) internal pure returns (uint256, uint256) {
        for (uint256 i = 0; i < _chainCounts.length; i++) {
            if (_chainCounts[i].remoteEid == _remoteEid) {
                return (_chainCounts[i].inboundCount, _chainCounts[i].outboundCount);
            }
        }
        return (0, 0);
    }

    function _getPreCrimePeers(
        InboundPacket[] memory _packets
    ) internal view override returns (PreCrimePeer[] memory peers) {
        PreCrimePeer[] memory allPeers = preCrimePeers;
        PreCrimePeer[] memory peersTmp = new PreCrimePeer[](_packets.length);

        int256 cursor = -1;
        for (uint256 i = 0; i < _packets.length; i++) {
            uint32 srcEid = _packets[i].origin.srcEid;

            // push src eid & peer
            int256 index = _indexOf(allPeers, srcEid);
            if (index >= 0 && _indexOf(peersTmp, srcEid) < 0) {
                cursor++;
                peersTmp[uint256(cursor)] = allPeers[uint256(index)];
            }
        }
        // copy to return
        if (cursor >= 0) {
            uint256 len = uint256(cursor) + 1;
            peers = new PreCrimePeer[](len);
            for (uint256 i = 0; i < len; i++) {
                peers[i] = peersTmp[i];
            }
        }
    }

    function _indexOf(PreCrimePeer[] memory _peers, uint32 _eid) internal pure returns (int256) {
        for (uint256 i = 0; i < _peers.length; i++) {
            if (_peers[i].eid == _eid) return int256(i);
        }
        return -1;
    }
}
