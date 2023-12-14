// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { Packet } from "../../contracts/interfaces/ISendLib.sol";
import { AddressCast } from "../../contracts/libs/AddressCast.sol";
import { PacketV1Codec } from "../../contracts/messagelib/libs/PacketV1Codec.sol";
import { SimpleMessageLib } from "../../contracts/messagelib/SimpleMessageLib.sol";
import { EndpointV2 } from "../../contracts/EndpointV2.sol";
import { EndpointV2Alt } from "../../contracts/EndpointV2Alt.sol";

import { TreasuryMock } from "../mocks/TreasuryMock.sol";

contract LayerZeroTest is Test {
    uint32 internal localEid;
    uint32 internal remoteEid;
    EndpointV2 internal endpoint;
    SimpleMessageLib internal simpleMsgLib;
    address internal blockedLibrary;

    function setUp() public virtual {
        localEid = 1;
        remoteEid = 2;
        (endpoint, simpleMsgLib) = setupEndpointWithSimpleMsgLib(localEid);
        setDefaultMsgLib(endpoint, address(simpleMsgLib), remoteEid);
        blockedLibrary = endpoint.blockedLibrary();
    }

    function setUpEndpoint(uint32 _eid) public returns (EndpointV2) {
        return new EndpointV2(_eid, address(this));
    }

    function setupEndpointAlt(uint32 _eid, address _altToken) public returns (EndpointV2Alt) {
        return new EndpointV2Alt(_eid, address(this), _altToken);
    }

    function setupEndpointWithSimpleMsgLib(uint32 _eid) public returns (EndpointV2, SimpleMessageLib) {
        EndpointV2 e = setUpEndpoint(_eid);

        TreasuryMock treasuryMock = new TreasuryMock();
        SimpleMessageLib msgLib = new SimpleMessageLib(address(e), address(treasuryMock));

        // register msg lib
        e.registerLibrary(address(msgLib));

        return (e, msgLib);
    }

    function setupSimpleMessageLib(
        address _endpoint,
        uint32 _remoteEid,
        bool _isDefault
    ) public returns (SimpleMessageLib) {
        TreasuryMock treasuryMock = new TreasuryMock();
        SimpleMessageLib msgLib = new SimpleMessageLib(_endpoint, address(treasuryMock));

        EndpointV2 endPoint = EndpointV2(_endpoint);
        endPoint.registerLibrary(address(msgLib));

        if (_isDefault) setDefaultMsgLib(endPoint, address(msgLib), _remoteEid);

        return msgLib;
    }

    function setDefaultMsgLib(EndpointV2 _endpoint, address _msglib, uint32 _remoteEid) public {
        _endpoint.setDefaultSendLibrary(_remoteEid, _msglib);
        _endpoint.setDefaultReceiveLibrary(_remoteEid, _msglib, 0);
    }

    function newPacket(
        uint64 _nonce,
        uint32 _srcEid,
        address _sender,
        uint32 _dstEid,
        bytes32 _receiver,
        bytes memory _message
    ) public pure returns (Packet memory) {
        bytes32 guid = keccak256(abi.encodePacked(_nonce, _srcEid, AddressCast.toBytes32(_sender), _dstEid, _receiver));
        return Packet(_nonce, _srcEid, _sender, _dstEid, _receiver, guid, _message);
    }

    function newAndEncodePacket(
        uint64 _nonce,
        uint32 _srcEid,
        address _sender,
        uint32 _dstEid,
        bytes32 _receiver,
        bytes memory _message
    ) public pure returns (bytes memory) {
        Packet memory packet = newPacket(_nonce, _srcEid, _sender, _dstEid, _receiver, _message);
        return PacketV1Codec.encode(packet);
    }
}
