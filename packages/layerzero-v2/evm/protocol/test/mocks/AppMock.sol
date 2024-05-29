// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ILayerZeroEndpointV2, Origin } from "../../contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroComposer } from "../../contracts/interfaces/ILayerZeroComposer.sol";
import { ILayerZeroReceiver } from "../../contracts/interfaces/ILayerZeroReceiver.sol";

// demonstrate how to external apps (bar) compose layerzero apps (foo)
// source: bar calls foo.send()
// destination: foo received the message and execute a trailing call
contract OAppMock is ILayerZeroReceiver {
    error InvalidMessage();

    bytes public constant FOO_MESSAGE = "foo";
    bytes public constant BAR_MESSAGE = "bar";

    address public immutable endpoint;
    address public immutable composer;

    mapping(uint32 => mapping(bytes32 => bool)) public pathwayBlacklist;

    constructor(address _endpoint) {
        endpoint = _endpoint;
        composer = address(new ComposerMock(address(this)));
    }

    function lzReceive(
        Origin calldata /*_origin*/,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) public payable {
        if (keccak256(_message) != keccak256(FOO_MESSAGE)) {
            revert InvalidMessage();
        }

        bytes memory message = bytes.concat(_message, BAR_MESSAGE);
        ILayerZeroEndpointV2(endpoint).sendCompose(composer, _guid, 0, message);
    }

    function allowInitializePath(Origin calldata _origin) public view override returns (bool) {
        return !pathwayBlacklist[_origin.srcEid][_origin.sender];
    }

    function nextNonce(uint32 /*_srcEid*/, bytes32 /*_sender*/) public pure override returns (uint64) {
        return 0;
    }

    function blacklistPathway(uint32 _srcEid, bytes32 _sender) public {
        pathwayBlacklist[_srcEid][_sender] = true;
    }

    function unBlacklistPathway(uint32 _srcEid, bytes32 _sender) public {
        pathwayBlacklist[_srcEid][_sender] = false;
    }
}

contract ComposerMock is ILayerZeroComposer {
    error InvalidMessage();
    error InvalidOApp();

    address public immutable oapp;
    uint256 public count;

    constructor(address _oapp) {
        oapp = _oapp;
    }

    function lzCompose(
        address _oapp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address,
        bytes calldata
    ) external payable override {
        if (_oapp != address(oapp)) {
            revert InvalidOApp();
        }

        if (keccak256(_message) != keccak256("foobar")) {
            revert InvalidMessage();
        }
        count += 1;
    }
}
