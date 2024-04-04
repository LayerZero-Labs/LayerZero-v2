// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BytesLib} from "solidity-bytes-utils/contracts/BytesLib.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {IPreCrime, PreCrimePeer} from "./interfaces/IPreCrime.sol";
import {IOAppPreCrimeSimulator} from "./interfaces/IOAppPreCrimeSimulator.sol";
import {InboundPacket, PacketDecoder} from "./libs/Packet.sol";

abstract contract PreCrimeUpgradeable is OwnableUpgradeable, IPreCrime {
    using BytesLib for bytes;

    struct PreCrimeStorage {
        // preCrime config
        uint64 maxBatchSize;
        PreCrimePeer[] preCrimePeers;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzerov2.storage.precrime")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PreCrimeStorageLocation =
        0x56af11d8938063b7ae95a808f88d40c589be3bbf4cb6facdbc642a7b38e01f00;

    uint16 internal constant CONFIG_VERSION = 2;
    address internal constant OFF_CHAIN_CALLER = address(0xDEAD);

    address internal immutable lzEndpoint;
    address public immutable simulator;
    address public immutable oApp;

    /// @dev getConfig(), simulate() and preCrime() are not view functions because it is more flexible to be able to
    ///      update state for some complex logic. So onlyOffChain() modifier is to make sure they are only called
    ///      by the off-chain.
    modifier onlyOffChain() {
        if (msg.sender != OFF_CHAIN_CALLER) revert OnlyOffChain();
        _;
    }

    function _getPreCrimeStorage() internal pure returns (PreCrimeStorage storage $) {
        assembly {
            $.slot := PreCrimeStorageLocation
        }
    }

    constructor(address _endpoint, address _simulator) {
        lzEndpoint = _endpoint;
        simulator = _simulator;
        oApp = IOAppPreCrimeSimulator(_simulator).oApp();
    }

    /**
     * @dev Ownable is not initialized here on purpose. It should be initialized in the child contract to
     * accommodate the different version of Ownable.
     */
    function __PreCrime_init() internal onlyInitializing {}

    function __PreCrime_init_unchained() internal onlyInitializing {}

    function maxBatchSize() external view returns (uint64) {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        return $.maxBatchSize;
    }

    function setMaxBatchSize(uint64 _maxBatchSize) external onlyOwner {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        $.maxBatchSize = _maxBatchSize;
    }

    function setPreCrimePeers(PreCrimePeer[] calldata _preCrimePeers) external onlyOwner {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        delete $.preCrimePeers;
        for (uint256 i = 0; i < _preCrimePeers.length; ++i) {
            $.preCrimePeers.push(_preCrimePeers[i]);
        }
    }

    function getPreCrimePeers() external view returns (PreCrimePeer[] memory) {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        return $.preCrimePeers;
    }

    function getConfig(bytes[] calldata _packets, uint256[] calldata _packetMsgValues)
        external
        onlyOffChain
        returns (bytes memory)
    {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        bytes memory config = abi.encodePacked(CONFIG_VERSION, $.maxBatchSize);

        // if no packets, return config with all peers
        PreCrimePeer[] memory peers =
            _packets.length == 0 ? $.preCrimePeers : _getPreCrimePeers(PacketDecoder.decode(_packets, _packetMsgValues));

        if (peers.length > 0) {
            uint16 size = uint16(peers.length);
            config = abi.encodePacked(config, size);

            for (uint256 i = 0; i < size; ++i) {
                config = abi.encodePacked(config, peers[i].eid, peers[i].preCrime, peers[i].oApp);
            }
        }

        return config;
    }

    // @dev _packetMsgValues refers to the 'lzReceive' option passed per packet
    function simulate(bytes[] calldata _packets, uint256[] calldata _packetMsgValues)
        external
        payable
        override
        onlyOffChain
        returns (bytes memory)
    {
        InboundPacket[] memory packets = PacketDecoder.decode(_packets, _packetMsgValues);
        _checkPacketSizeAndOrder(packets);
        return _simulate(packets);
    }

    function preCrime(bytes[] calldata _packets, uint256[] calldata _packetMsgValues, bytes[] calldata _simulations)
        external
        onlyOffChain
    {
        InboundPacket[] memory packets = PacketDecoder.decode(_packets, _packetMsgValues);
        uint32[] memory eids = new uint32[](_simulations.length);
        bytes[] memory simulations = new bytes[](_simulations.length);

        for (uint256 i = 0; i < _simulations.length; ++i) {
            bytes calldata simulation = _simulations[i];
            eids[i] = uint32(bytes4(simulation[0:4]));
            simulations[i] = simulation[4:];
        }
        _checkResultsCompleteness(packets, eids);

        _preCrime(packets, eids, simulations);
    }

    function version() external pure returns (uint64 major, uint8 minor) {
        return (2, 0);
    }

    function preCrimePeers() internal view returns (PreCrimePeer[] storage) {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        return $.preCrimePeers;
    }

    function _checkResultsCompleteness(InboundPacket[] memory _packets, uint32[] memory _eids) internal {
        // check if all peers result included
        if (_packets.length > 0) {
            PreCrimePeer[] memory peers = _getPreCrimePeers(_packets);
            for (uint256 i = 0; i < peers.length; i++) {
                uint32 expectedEid = peers[i].eid;
                if (!_isContain(_eids, expectedEid)) revert SimulationResultNotFound(expectedEid);
            }
        }

        // check if local result included
        uint32 localEid = _getLocalEid();
        if (!_isContain(_eids, localEid)) revert SimulationResultNotFound(localEid);
    }

    function _isContain(uint32[] memory _array, uint32 _item) internal pure returns (bool) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _item) return true;
        }
        return false;
    }

    function _checkPacketSizeAndOrder(InboundPacket[] memory _packets) internal view {
        PreCrimeStorage storage $ = _getPreCrimeStorage();
        if (_packets.length > $.maxBatchSize) revert PacketOversize($.maxBatchSize, _packets.length);

        // check packets nonce, sequence order
        // packets should group by srcEid and sender, then sort by nonce ascending
        if (_packets.length > 0) {
            uint32 srcEid;
            bytes32 sender;
            uint64 nonce;
            for (uint256 i = 0; i < _packets.length; i++) {
                InboundPacket memory packet = _packets[i];

                // skip if not from trusted peer
                if (!IOAppPreCrimeSimulator(simulator).isPeer(packet.origin.srcEid, packet.origin.sender)) continue;

                // start from a new chain or a new source oApp
                if (packet.origin.srcEid != srcEid || packet.origin.sender != sender) {
                    srcEid = packet.origin.srcEid;
                    sender = packet.origin.sender;
                    nonce = _getInboundNonce(srcEid, sender);
                }
                // TODO ??
                // Wont the nonce order not matter and enforced at the OApp level? the simulation will revert?

                // the following packet's nonce add 1 in order
                if (packet.origin.nonce != ++nonce) revert PacketUnsorted();
            }
        }
    }

    function _simulate(InboundPacket[] memory _packets) internal virtual returns (bytes memory) {
        (bool success, bytes memory returnData) = simulator.call{value: msg.value}(
            abi.encodeWithSelector(IOAppPreCrimeSimulator.lzReceiveAndRevert.selector, _packets)
        );

        bytes memory result = _parseRevertResult(success, returnData);
        return abi.encodePacked(_getLocalEid(), result); // add localEid at the first of the result
    }

    function _parseRevertResult(bool _success, bytes memory _returnData) internal pure returns (bytes memory result) {
        // should always revert with LzReceiveRevert
        if (_success) revert SimulationFailed("no revert");

        // if not expected selector, bubble up error
        if (bytes4(_returnData) != IOAppPreCrimeSimulator.SimulationResult.selector) {
            revert SimulationFailed(_returnData);
        }

        // Slice the sighash. Remove the selector which is the first 4 bytes
        result = _returnData.slice(4, _returnData.length - 4);
        result = abi.decode(result, (bytes));
    }

    // to be compatible with EndpointV1
    function _getLocalEid() internal view virtual returns (uint32) {
        return ILayerZeroEndpointV2(lzEndpoint).eid();
    }

    // to be compatible with EndpointV1
    function _getInboundNonce(uint32 _srcEid, bytes32 _sender) internal view virtual returns (uint64) {
        return ILayerZeroEndpointV2(lzEndpoint).inboundNonce(oApp, _srcEid, _sender);
    }

    // ----------------- to be implemented -----------------
    function buildSimulationResult() external view virtual override returns (bytes memory);

    function _getPreCrimePeers(InboundPacket[] memory _packets)
        internal
        virtual
        returns (PreCrimePeer[] memory peers);

    function _preCrime(InboundPacket[] memory _packets, uint32[] memory _eids, bytes[] memory _simulations)
        internal
        virtual;
}
